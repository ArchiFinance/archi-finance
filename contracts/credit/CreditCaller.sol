// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Multicall } from "../libraries/Multicall.sol";

import { IAddressProvider } from "../interfaces/IAddressProvider.sol";
import { IClaim } from "../interfaces/IClaim.sol";
import { IAbstractReward } from "../rewards/interfaces/IAbstractReward.sol";
import { IVaultRewardDistributor } from "../rewards/interfaces/IVaultRewardDistributor.sol";
import { ICreditManager } from "./interfaces/ICreditManager.sol";
import { ICreditToken } from "./interfaces/ICreditToken.sol";
import { ICreditUser } from "./interfaces/ICreditUser.sol";
import { ICreditLiquidator } from "./interfaces/ICreditLiquidator.sol";
import { IPriceOracle } from "../oracles/interfaces/IPriceOracle.sol";
import { IDeposter } from "../depositers/interfaces/IDeposter.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { ICreditCaller } from "./interfaces/ICreditCaller.sol";

contract CreditCaller is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, Multicall, ICreditCaller {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_RATIO = 100; // min ratio is 1
    uint256 private constant MAX_RATIO = 1000; // max ratio is 10
    uint256 private constant RATIO_PRECISION = 100;
    uint256 private constant MAX_SUM_RATIO = 10;
    uint256 private constant LIQUIDATE_THRESHOLD = 100; // 10%
    uint256 private constant LIQUIDATE_DENOMINATOR = 1000;

    struct Strategy {
        bool listed;
        address collateralReward;
        mapping(address => address) vaultReward; // vaults => VaultRewardDistributor
    }

    address public addressProvider;
    address public wethAddress;
    address public creditUser;
    address public creditToken;

    mapping(address => Strategy) public strategies;
    mapping(address => address) public vaultManagers; // borrow token => manager
    mapping(address => uint256) public tokenDecimals;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function initialize(address _addressProvider, address _wethAddress) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();

        addressProvider = _addressProvider;
        wethAddress = _wethAddress;
    }

    function openLendCredit(
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable override nonReentrant {
        require(_token != address(0), "CreditCaller: Token cannot be 0x0");
        require(_amountIn > 0, "CreditCaller: Amount cannot be 0");

        if (_token == ZERO) {
            _wrapETH(_amountIn);

            _token = wethAddress;
        } else {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;
        }

        _approve(_token, _depositer, _amountIn);

        (, uint256 collateralMintedAmount) = IDeposter(_depositer).mint(_token, _amountIn);

        ICreditUser.UserLendCredit memory userLendCredit;

        userLendCredit.depositer = _depositer;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.borrowedTokens = _borrowedTokens;
        userLendCredit.ratios = _ratios;

        return _lendCredit(userLendCredit, collateralMintedAmount, _recipient);
    }

    function _lendCredit(
        ICreditUser.UserLendCredit memory _userLendCredit,
        uint256 _collateralMintedAmount,
        address _recipient
    ) internal {
        _requireValidRatio(_userLendCredit.ratios);

        Strategy storage strategy = strategies[_userLendCredit.depositer];

        require(strategy.listed, "CreditCaller: Mismatched strategy");
        require(_userLendCredit.borrowedTokens.length == _userLendCredit.ratios.length, "CreditCaller: Length mismatch");

        uint256 borrowedIndex = ICreditUser(creditUser).accrueSnapshot(_recipient);

        ICreditUser(creditUser).createUserLendCredit(
            _recipient,
            borrowedIndex,
            _userLendCredit.depositer,
            _userLendCredit.token,
            _userLendCredit.amountIn,
            _userLendCredit.borrowedTokens,
            _userLendCredit.ratios
        );

        uint256[] memory borrowedAmountOuts = new uint256[](_userLendCredit.borrowedTokens.length);
        uint256[] memory borrowedMintedAmount = new uint256[](_userLendCredit.borrowedTokens.length);
        address[] memory creditManagers = new address[](_userLendCredit.borrowedTokens.length);

        for (uint256 i = 0; i < _userLendCredit.borrowedTokens.length; i++) {
            borrowedAmountOuts[i] = calcBorrowAmount(
                _userLendCredit.amountIn,
                _userLendCredit.token,
                _userLendCredit.ratios[i],
                _userLendCredit.borrowedTokens[i]
            );
            creditManagers[i] = vaultManagers[_userLendCredit.borrowedTokens[i]];

            _approve(_userLendCredit.borrowedTokens[i], _userLendCredit.depositer, borrowedAmountOuts[i]);

            ICreditManager(creditManagers[i]).borrow(_recipient, borrowedAmountOuts[i]);

            (, borrowedMintedAmount[i]) = IDeposter(_userLendCredit.depositer).mint(_userLendCredit.borrowedTokens[i], borrowedAmountOuts[i]);

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(creditManagers[i]).vault()];

            _mintTokenAndApprove(vaultRewardDistributor, borrowedMintedAmount[i]);
            IVaultRewardDistributor(vaultRewardDistributor).stake(borrowedMintedAmount[i]);

            emit CalcBorrowAmount(_userLendCredit.borrowedTokens[i], borrowedAmountOuts[i], borrowedMintedAmount[i]);
        }

        _mintTokenAndApprove(strategy.collateralReward, _collateralMintedAmount);

        IAbstractReward(strategy.collateralReward).stakeFor(_recipient, _collateralMintedAmount);

        ICreditUser(creditUser).createUserBorrowed(
            _recipient,
            borrowedIndex,
            creditManagers,
            borrowedAmountOuts,
            _collateralMintedAmount,
            borrowedMintedAmount
        );

        emit LendCredit(
            _recipient,
            _userLendCredit.depositer,
            _userLendCredit.token,
            _userLendCredit.amountIn,
            _userLendCredit.borrowedTokens,
            _userLendCredit.ratios
        );
    }

    function _mintTokenAndApprove(address _spender, uint256 _amountIn) internal {
        ICreditToken(creditToken).mint(address(this), _amountIn);
        _approve(creditToken, _spender, _amountIn);
    }

    function repayCredit(uint256 _borrowedIndex) external override nonReentrant returns (uint256) {
        uint256 lastestIndex = ICreditUser(creditUser).getUserCounts(msg.sender);

        require(_borrowedIndex > 0, "CreditCaller: Minimum limit exceeded");
        require(_borrowedIndex <= lastestIndex, "CreditCaller: Index out of range");

        bool isTerminated = ICreditUser(creditUser).isTerminated(msg.sender, _borrowedIndex);

        require(!isTerminated, "CreditCaller: Already terminated");

        return _repayCredit(msg.sender, _borrowedIndex);
    }

    function _repayCredit(address _recipient, uint256 _borrowedIndex) public returns (uint256) {
        ICreditUser.UserLendCredit memory userLendCredit;
        ICreditUser.UserBorrowed memory userBorrowed;

        (userLendCredit.depositer, userLendCredit.token, , userLendCredit.borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(
            _recipient,
            _borrowedIndex
        );

        uint256 totalMintedAmount;

        (
            userBorrowed.creditManagers,
            userBorrowed.borrowedAmountOuts,
            userBorrowed.collateralMintedAmount,
            userBorrowed.borrowedMintedAmount,
            totalMintedAmount
        ) = ICreditUser(creditUser).getUserBorrowed(_recipient, _borrowedIndex);

        Strategy storage strategy = strategies[userLendCredit.depositer];

        for (uint256 i = 0; i < userBorrowed.creditManagers.length; i++) {
            uint256 usedMintedAmount = _withdrawBorrowedAmount(userLendCredit.depositer, userLendCredit.borrowedTokens[i], userBorrowed.borrowedAmountOuts[i]);

            totalMintedAmount = totalMintedAmount.sub(usedMintedAmount);

            _approve(userLendCredit.borrowedTokens[i], userBorrowed.creditManagers[i], userBorrowed.borrowedAmountOuts[i]);
            ICreditManager(userBorrowed.creditManagers[i]).repay(_recipient, userBorrowed.borrowedAmountOuts[i]);

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(userBorrowed.creditManagers[i]).vault()];

            IVaultRewardDistributor(vaultRewardDistributor).withdraw(userBorrowed.borrowedMintedAmount[i]);

            ICreditToken(creditToken).burn(address(this), userBorrowed.borrowedMintedAmount[i]);
        }

        uint256 collateralAmountOut = IDeposter(userLendCredit.depositer).withdraw(userLendCredit.token, totalMintedAmount, 0);

        IERC20Upgradeable(userLendCredit.token).safeTransfer(_recipient, collateralAmountOut);
        IAbstractReward(strategy.collateralReward).withdrawFor(_recipient, userBorrowed.collateralMintedAmount);
        ICreditToken(creditToken).burn(address(this), userBorrowed.collateralMintedAmount);
        ICreditUser(creditUser).destroy(_recipient, _borrowedIndex);

        emit RepayCredit(_recipient, _borrowedIndex, collateralAmountOut);

        return collateralAmountOut;
    }

    function _withdrawBorrowedAmount(
        address _depositer,
        address _borrowedTokens,
        uint256 _borrowedAmountOuts
    ) internal returns (uint256) {
        uint256 usedMintedAmount = _sellGlpFromAmount(_borrowedTokens, _borrowedAmountOuts);
       
        uint256 amountOut = IDeposter(_depositer).withdraw(_borrowedTokens, usedMintedAmount, 0);
      
        require(amountOut >= _borrowedAmountOuts, "CreditCaller: Insufficient balance");

        return usedMintedAmount;
    }

    function liquidate(address _recipient, uint256 _borrowedIndex) external override nonReentrant {
        uint256 lastestIndex = ICreditUser(creditUser).getUserCounts(_recipient);

        require(_borrowedIndex > 0, "CreditCaller: Minimum limit exceeded");
        require(_borrowedIndex <= lastestIndex, "CreditCaller: Index out of range");

        bool isTerminated = ICreditUser(creditUser).isTerminated(_recipient, _borrowedIndex);

        require(!isTerminated, "CreditCaller: Already terminated");

        (, , , address[] memory borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(_recipient, _borrowedIndex);
        (address[] memory creditManagers, uint256[] memory borrowedAmountOuts, , , uint256 mintedAmount) = ICreditUser(creditUser).getUserBorrowed(
            _recipient,
            _borrowedIndex
        );

        uint256 borrowedMinted;

        for (uint256 i = 0; i < creditManagers.length; i++) {
            borrowedMinted = borrowedMinted.add(_sellGlpFromAmount(borrowedTokens[i], borrowedAmountOuts[i]));
        }

        uint256 health = mintedAmount.sub(borrowedMinted).mul(LIQUIDATE_DENOMINATOR).div(mintedAmount);

        if (health <= LIQUIDATE_THRESHOLD) {
            _repayCredit(_recipient, _borrowedIndex);
        }

        emit Liquidate(_recipient, _borrowedIndex, health);
    }

    function addStrategy(
        address _depositer,
        address _collateralReward,
        address[] calldata _vaults,
        address[] calldata _vaultRewards
    ) external onlyOwner {
        require(_vaults.length == _vaultRewards.length, "CreditCaller: Length mismatch");

        Strategy storage strategy = strategies[_depositer];

        strategy.listed = true;
        strategy.collateralReward = _collateralReward;

        for (uint256 i = 0; i < _vaults.length; i++) {
            strategy.vaultReward[_vaults[i]] = _vaultRewards[i];
        }

        emit AddStrategy(_depositer, _collateralReward, _vaults, _vaultRewards);
    }

    function addVaultManager(address _underlyingToken, address _creditManager) external onlyOwner {
        require(vaultManagers[_underlyingToken] == address(0), "CreditCaller: Cannot run this function twice");

        vaultManagers[_underlyingToken] = _creditManager;

        emit AddVaultManager(_underlyingToken, _creditManager);
    }

    function setCreditUser(address _creditUser) external onlyOwner {
        require(creditUser == address(0), "CreditCaller: Cannot run this function twice");
        creditUser = _creditUser;

        emit SetCreditUser(_creditUser);
    }

    function setCreditToken(address _creditToken) external onlyOwner {
        require(creditToken == address(0), "CreditCaller: Cannot run this function twice");
        creditToken = _creditToken;

        emit SetCreditToken(_creditToken);
    }

    function setTokenDecimals(address _underlyingToken, uint256 _decimals) external onlyOwner {
        tokenDecimals[_underlyingToken] = _decimals;

        emit SetTokenDecimals(_underlyingToken, _decimals);
    }

    function claimFor(address _target, address _recipient) external nonReentrant {
        IClaim(_target).claim(_recipient);
    }

    function _calcFormula(
        uint256 _collateralAmountIn,
        address _collateralToken,
        uint256 _ratio,
        address _borrowedToken
    ) internal view returns (uint256) {
        uint256 collateralPrice = _tokenPrice(_collateralToken);
        uint256 borrowedPrice = _tokenPrice(_borrowedToken);

        return _collateralAmountIn.mul(collateralPrice).mul(_ratio).div(RATIO_PRECISION).div(borrowedPrice);
    }

    function calcBorrowAmount(
        uint256 _collateralAmountIn,
        address _collateralToken,
        uint256 _ratio,
        address _borrowedToken
    ) public view returns (uint256) {
        uint256 collateralDecimals = 10**tokenDecimals[_collateralToken];
        uint256 borrowedTokenDecimals = 10**tokenDecimals[_borrowedToken];

        return _calcFormula(_collateralAmountIn, _collateralToken, _ratio, _borrowedToken).mul(borrowedTokenDecimals).div(collateralDecimals);
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _requireValidRatio(uint256[] memory _ratios) internal pure {
        require(_ratios.length > 0, "CreditCaller: Ratios cannot be empty");

        uint256 total;

        for (uint256 i = 0; i < _ratios.length; i++) total = total.add(_ratios[i]);

        require(total <= MAX_RATIO, "CreditCaller: MAX_RATIO limit exceeded");
        require(total >= MIN_RATIO, "CreditCaller: MIN_RATIO limit exceeded");
    }

    function _tokenPrice(address _token) internal view returns (uint256) {
        address priceOracle = IAddressProvider(addressProvider).getPriceOracle();

        return IPriceOracle(priceOracle).getPrice(_token);
    }

    function _sellGlpFromAmount(address _swapToken, uint256 _amountIn) internal view returns (uint256) {
        address liquidator = IAddressProvider(addressProvider).getLiquidator();

        (uint256 amountOut, ) = ICreditLiquidator(liquidator).getSellGlpFromAmount(_swapToken, _amountIn);

        uint256 priceDecimals = 30;
        uint256 glpDecimals = 18;

        return ICreditLiquidator(liquidator).adjustForDecimals(amountOut, priceDecimals, glpDecimals);
    }

    function _wrapETH(uint256 _amountIn) internal {
        require(msg.value == _amountIn, "CreditCaller: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }
}
