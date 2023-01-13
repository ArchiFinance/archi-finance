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
import { ICollateralReward } from "../rewards/interfaces/ICollateralReward.sol";
import { IVaultRewardDistributor } from "../rewards/interfaces/IVaultRewardDistributor.sol";
import { ICreditManager } from "./interfaces/ICreditManager.sol";
import { ICreditToken } from "./interfaces/ICreditToken.sol";
import { ICreditUser } from "./interfaces/ICreditUser.sol";
import { ICreditLiquidator } from "./interfaces/ICreditLiquidator.sol";
import { IPriceOracle } from "../oracles/interfaces/IPriceOracle.sol";
import { IDeposter } from "../depositers/interfaces/IDeposter.sol";
import { IGmxRewardRouter } from "../depositers/interfaces/IGmxRewardRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { ICreditCaller } from "./interfaces/ICreditCaller.sol";

contract CreditCaller is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, Multicall, ICreditCaller {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
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
    address public creditUser;
    address public creditToken;

    mapping(address => Strategy) public strategies;
    mapping(address => address) public vaultManagers; // borrow token => manager

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function initialize(address _addressProvider) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();

        addressProvider = _addressProvider;
    }

    function lendCreditGLP(
        address _depositer,
        address _targetToken,
        uint256 _glpAmountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) public {
        require(_glpAmountIn > 0, "CreditCaller: Glp amount cannot be 0");

        if (_targetToken == ZERO) {
            _targetToken = WETH;
        }

        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        IERC20Upgradeable(IGmxRewardRouter(router).stakedGlpTracker()).safeTransferFrom(msg.sender, address(this), _glpAmountIn);

        uint256 amountOut = _sellGlpToAmount(_targetToken, _glpAmountIn);

        emit LendCreditGLP(msg.sender, _depositer, _targetToken, _glpAmountIn, _borrowedTokens, _ratios);

        return _lendCredit(_depositer, _targetToken, amountOut, _borrowedTokens, _ratios, _glpAmountIn);
    }

    function lendCredit(
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) public payable {
        require(_amountIn > 0, "CreditCaller: Amount cannot be 0");

        if (msg.value > 0) {
            require(msg.value == _amountIn, "CreditCaller: ETH amount mismatch");

            IWETH(WETH).deposit{ value: _amountIn }();

            _token = WETH;
        } else {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;
        }

        _approve(_token, _depositer, _amountIn);

        (, uint256 collateralMintedAmount) = IDeposter(_depositer).mint(_token, _amountIn);

        return _lendCredit(_depositer, _token, _amountIn, _borrowedTokens, _ratios, collateralMintedAmount);
    }

    function _lendCredit(
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        uint256 _collateralMintedAmount
    ) internal {
        _requireValidRatio(_ratios);

        Strategy storage strategy = strategies[_depositer];
        require(strategy.listed, "CreditCaller: Mismatched strategy");

        require(_borrowedTokens.length == _ratios.length, "CreditCaller: Length mismatch");

        uint256 borrowedIndex = ICreditUser(creditUser).accrueSnapshot(msg.sender);

        ICreditUser(creditUser).createUserLendCredit(msg.sender, borrowedIndex, _depositer, _token, _amountIn, _borrowedTokens, _ratios);

        uint256[] memory borrowedAmountOuts = new uint256[](_borrowedTokens.length);
        uint256[] memory borrowedMintedAmount = new uint256[](_borrowedTokens.length);
        address[] memory creditManagers = new address[](_borrowedTokens.length);

        for (uint256 i = 0; i < _borrowedTokens.length; i++) {
            borrowedAmountOuts[i] = calcBorrowAmount(_amountIn, _token, _ratios[i], _borrowedTokens[i]);
            creditManagers[i] = vaultManagers[_borrowedTokens[i]];

            _approve(_borrowedTokens[i], _depositer, borrowedAmountOuts[i]);

            ICreditManager(creditManagers[i]).borrow(msg.sender, borrowedAmountOuts[i]);

            (, borrowedMintedAmount[i]) = IDeposter(_depositer).mint(_borrowedTokens[i], borrowedAmountOuts[i]);

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(creditManagers[i]).vault()];

            _mintTokenAndApprove(vaultRewardDistributor, borrowedMintedAmount[i]);
            IVaultRewardDistributor(vaultRewardDistributor).stake(borrowedMintedAmount[i]);
        }

        _mintTokenAndApprove(strategy.collateralReward, _collateralMintedAmount);

        ICollateralReward(strategy.collateralReward).stakeFor(msg.sender, _collateralMintedAmount);

        ICreditUser(creditUser).createUserBorroweds(
            msg.sender,
            borrowedIndex,
            creditManagers,
            borrowedAmountOuts,
            _collateralMintedAmount,
            borrowedMintedAmount
        );

        emit LendCredit(msg.sender, _depositer, _token, _amountIn, _borrowedTokens, _ratios);
    }

    function _mintTokenAndApprove(address _spender, uint256 _amountIn) internal {
        ICreditToken(creditToken).mint(address(this), _amountIn);
        _approve(creditToken, _spender, _amountIn);
    }

    function repayCredit(uint256 _borrowedIndex) public returns (uint256) {
        uint256 lastestIndex = ICreditUser(creditUser).getUserCounts(msg.sender);

        require(_borrowedIndex > 0, "CreditCaller: Minimum limit exceeded");
        require(_borrowedIndex <= lastestIndex, "CreditCaller: Index out of range");

        bool isTerminated = ICreditUser(creditUser).isTerminated(msg.sender, _borrowedIndex);

        require(!isTerminated, "CreditCaller: Already terminated");

        return _repayCredit(msg.sender, _borrowedIndex);
    }

    function _repayCredit(address _recipient, uint256 _borrowedIndex) public returns (uint256) {
        (address depositer, address token, , address[] memory borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(_recipient, _borrowedIndex);

        (
            address[] memory creditManagers,
            uint256[] memory borrowedAmountOuts,
            uint256 collateralMintedAmount,
            uint256[] memory borrowedMintedAmount,
            uint256 mintedAmount
        ) = ICreditUser(creditUser).getUserBorrowed(_recipient, _borrowedIndex);

        Strategy storage strategy = strategies[depositer];

        for (uint256 i = 0; i < creditManagers.length; i++) {
            uint256 availableMintedAmount = _sellGlpFromAmount(borrowedTokens[i], borrowedAmountOuts[i]);

            IDeposter(depositer).withdraw(borrowedTokens[i], availableMintedAmount, borrowedAmountOuts[i]);

            _approve(borrowedTokens[i], creditManagers[i], borrowedAmountOuts[i]);
            ICreditManager(creditManagers[i]).repay(_recipient, borrowedAmountOuts[i]);
            mintedAmount = mintedAmount.sub(availableMintedAmount);

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(creditManagers[i]).vault()];

            IVaultRewardDistributor(vaultRewardDistributor).withdraw(borrowedMintedAmount[i]);

            ICreditToken(creditToken).burn(address(this), borrowedMintedAmount[i]);
        }

        uint256 collateralAmountOut = IDeposter(depositer).withdraw(token, mintedAmount, 0);

        IERC20Upgradeable(token).safeTransfer(_recipient, collateralAmountOut);

        ICollateralReward(strategy.collateralReward).withdrawFor(_recipient, collateralMintedAmount);
        ICreditToken(creditToken).burn(address(this), collateralMintedAmount);

        ICreditUser(creditUser).destroy(_recipient, _borrowedIndex);

        emit RepayCredit(_recipient, _borrowedIndex, collateralAmountOut);

        return collateralAmountOut;
    }

    function liquidate(address _recipient, uint256 _borrowedIndex) public {
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

        uint256 health = ((mintedAmount - borrowedMinted) * LIQUIDATE_DENOMINATOR) / mintedAmount;

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
    ) external {
        require(_vaults.length == _vaultRewards.length, "CreditCaller: Length mismatch");

        Strategy storage strategy = strategies[_depositer];

        strategy.listed = true;
        strategy.collateralReward = _collateralReward;

        for (uint256 i = 0; i < _vaults.length; i++) {
            strategy.vaultReward[_vaults[i]] = _vaultRewards[i];
        }

        emit AddStrategy(_depositer, _collateralReward, _vaults, _vaultRewards);
    }

    function addVaultManager(address _underlying, address _creditManager) external onlyOwner {
        require(vaultManagers[_underlying] == address(0), "CreditCaller: Cannot run this function twice");

        vaultManagers[_underlying] = _creditManager;

        emit AddVaultManager(_underlying, _creditManager);
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

    function calcBorrowAmount(
        uint256 _collateralAmountIn,
        address _collateralToken,
        uint256 _ratio,
        address _borrowedToken
    ) public view returns (uint256) {
        uint256 collateralPrice = _tokenPrice(_collateralToken);
        uint256 borrowedPrice = _tokenPrice(_borrowedToken);

        return (_collateralAmountIn * collateralPrice * _ratio) / RATIO_PRECISION / borrowedPrice;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _requireValidRatio(uint256[] calldata _ratios) internal pure {
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

    function _sellGlpToAmount(address _swapToken, uint256 _amountIn) internal view returns (uint256) {
        address liquidator = IAddressProvider(addressProvider).getLiquidator();

        (uint256 amountOut, ) = ICreditLiquidator(liquidator).getSellGlpToAmount(_swapToken, _amountIn);

        return amountOut;
    }
}
