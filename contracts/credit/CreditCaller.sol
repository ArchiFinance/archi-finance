// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { Multicall } from "../libraries/Multicall.sol";
import { IAddressProvider } from "../interfaces/IAddressProvider.sol";
import { IClaim } from "../interfaces/IClaim.sol";
import { IAllowlist } from "../interfaces/IAllowlist.sol";
import { IBaseReward } from "../rewards/interfaces/IBaseReward.sol";
import { IVaultRewardDistributor } from "../rewards/interfaces/IVaultRewardDistributor.sol";
import { ICreditManager } from "./interfaces/ICreditManager.sol";
import { ICreditTokenStaker } from "./interfaces/ICreditTokenStaker.sol";
import { ICreditUser } from "./interfaces/ICreditUser.sol";
import { ICreditAggregator } from "./interfaces/ICreditAggregator.sol";
import { IDepositor } from "../depositors/interfaces/IDepositor.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { ICreditCaller } from "./interfaces/ICreditCaller.sol";

/* 
This contract is used to call the CreditManager and implement loan repayment operations. 
Through the CreditCaller contract, 
users can use their ETH, BTC, USDC, USDT, FRAX, UNI, and LINK as collateral assets to obtain loans from the CreditManager. 
Afterwards, the contract will send all the assets to the Depositor, 
which will then pledge them to the GMX contract.
*/

contract CreditCaller is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, Multicall, ICreditCaller {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using AddressUpgradeable for address;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_RATIO = 100; // min ratio is 1
    uint256 private constant MAX_RATIO = 1000; // max ratio is 10
    uint256 private constant RATIO_PRECISION = 100;
    uint256 private constant MAX_SUM_RATIO = 10;
    uint256 private constant LIQUIDATE_THRESHOLD = 100; // 10%
    uint256 private constant LIQUIDATE_DENOMINATOR = 1000;
    uint256 private constant LIQUIDATE_FEE = 10; // 1%
    uint256 private constant LIQUIDATE_PRECISION = 1000;
    uint256 private constant MAX_LOAN_DURATION = 1 days * 365;

    struct Strategy {
        bool listed;
        address collateralReward;
        mapping(address => address) vaultReward; // vaults => VaultRewardDistributor
    }

    address public addressProvider;
    address public wethAddress;
    address public creditUser;
    address public creditTokenStaker;
    address public allowlist;

    mapping(address => Strategy) public strategies; // depositor => Strategy
    mapping(address => address) public vaultManagers; // borrow token => manager

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _addressProvider, address _wethAddress) external initializer {
        require(_addressProvider != address(0), "CreditCaller: _addressProvider cannot be 0x0");
        require(_wethAddress != address(0), "CreditCaller: _wethAddress cannot be 0x0");

        require(_addressProvider.isContract(), "CreditCaller: _addressProvider is not a contract");
        require(_wethAddress.isContract(), "CreditCaller: _wethAddress is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init_unchained();

        addressProvider = _addressProvider;
        wethAddress = _wethAddress;
    }

    /// @notice open position
    /// @param _depositor archi depositor address
    /// @param _token collateral token
    /// @param _amountIn collateral amount
    /// @param _borrowedTokens borrowed tokens
    /// @param _ratios leverage ratios
    /// @param _recipient borrower
    function openLendCredit(
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable override nonReentrant {
        require(_token != address(0), "CreditCaller: _token cannot be 0x0");
        require(_amountIn > 0, "CreditCaller: _amountIn cannot be 0");

        _requireValidRatio(_ratios);

        require(_borrowedTokens.length == _ratios.length, "CreditCaller: Length mismatch");

        if (allowlist != address(0)) {
            bool allowed = IAllowlist(allowlist).can(_recipient);

            require(allowed, "CreditCaller: Not whitelisted");
        }

        if (_token == ZERO) {
            _wrapETH(_amountIn);

            _token = wethAddress;
        } else {
            uint256 before = IERC20MetadataUpgradeable(_token).balanceOf(address(this));
            IERC20MetadataUpgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20MetadataUpgradeable(_token).balanceOf(address(this)) - before;
        }

        ICreditUser.UserLendCredit memory userLendCredit;

        userLendCredit.depositor = _depositor;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.borrowedTokens = _borrowedTokens;
        userLendCredit.ratios = _ratios;

        return _lendCredit(userLendCredit, _recipient);
    }

    function _lendCredit(ICreditUser.UserLendCredit memory _userLendCredit, address _recipient) internal {
        Strategy storage strategy = strategies[_userLendCredit.depositor];

        require(strategy.listed, "CreditCaller: Mismatched strategy");

        _approve(_userLendCredit.token, _userLendCredit.depositor, _userLendCredit.amountIn);

        (, uint256 collateralMintedAmount) = IDepositor(_userLendCredit.depositor).mint(_userLendCredit.token, _userLendCredit.amountIn);

        uint256 borrowedIndex = ICreditUser(creditUser).accrueSnapshot(_recipient);

        ICreditUser(creditUser).createUserLendCredit(
            _recipient,
            borrowedIndex,
            _userLendCredit.depositor,
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

            _approve(_userLendCredit.borrowedTokens[i], _userLendCredit.depositor, borrowedAmountOuts[i]);

            ICreditManager(creditManagers[i]).borrow(_recipient, borrowedAmountOuts[i]);

            (, borrowedMintedAmount[i]) = IDepositor(_userLendCredit.depositor).mint(_userLendCredit.borrowedTokens[i], borrowedAmountOuts[i]);

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(creditManagers[i]).vault()];

            ICreditTokenStaker(creditTokenStaker).stake(vaultRewardDistributor, borrowedMintedAmount[i]);

            emit CalcBorrowAmount(_userLendCredit.borrowedTokens[i], borrowedIndex, borrowedAmountOuts[i], borrowedMintedAmount[i]);
        }

        ICreditTokenStaker(creditTokenStaker).stakeFor(strategy.collateralReward, _recipient, collateralMintedAmount);

        ICreditUser(creditUser).createUserBorrowed(_recipient, borrowedIndex, creditManagers, borrowedAmountOuts, collateralMintedAmount, borrowedMintedAmount);

        emit LendCredit(
            _recipient,
            borrowedIndex,
            _userLendCredit.depositor,
            _userLendCredit.token,
            _userLendCredit.amountIn,
            _userLendCredit.borrowedTokens,
            _userLendCredit.ratios,
            block.timestamp
        );
    }

    /// @notice close position
    /// @param _borrowedIndex borrow index
    /// @return collateral amount
    function repayCredit(uint256 _borrowedIndex) external override nonReentrant returns (uint256) {
        uint256 lastestIndex = ICreditUser(creditUser).getUserCounts(msg.sender);

        require(_borrowedIndex > 0, "CreditCaller: Minimum limit exceeded");
        require(_borrowedIndex <= lastestIndex, "CreditCaller: Index out of range");

        bool isTerminated = ICreditUser(creditUser).isTerminated(msg.sender, _borrowedIndex);

        require(!isTerminated, "CreditCaller: Already terminated");

        return _repayCredit(msg.sender, _borrowedIndex, address(0));
    }

    function _repayCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _liquidator
    ) internal returns (uint256 collateralAmountOut) {
        ICreditUser.UserLendCredit memory userLendCredit;
        ICreditUser.UserBorrowed memory userBorrowed;

        (userLendCredit.depositor, userLendCredit.token, , userLendCredit.borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(
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

        Strategy storage strategy = strategies[userLendCredit.depositor];

        for (uint256 i = 0; i < userBorrowed.creditManagers.length; i++) {
            (uint256 usedMintedAmount, uint256 amountOut) = _withdrawBorrowedAmount(
                userLendCredit.depositor,
                userLendCredit.borrowedTokens[i],
                userBorrowed.borrowedAmountOuts[i]
            );

            uint256 repayAmountIn = userBorrowed.borrowedAmountOuts[i];

            if (_liquidator == address(0)) {
                require(amountOut >= repayAmountIn, "CreditCaller: Insufficient balance");
            } else {
                if (amountOut < repayAmountIn) {
                    emit RepayDebts(_recipient, _borrowedIndex, amountOut, repayAmountIn);

                    repayAmountIn = amountOut;
                }
            }

            _approve(userLendCredit.borrowedTokens[i], userBorrowed.creditManagers[i], repayAmountIn);
            ICreditManager(userBorrowed.creditManagers[i]).repay(_recipient, repayAmountIn);

            if (totalMintedAmount >= usedMintedAmount) {
                totalMintedAmount = totalMintedAmount - usedMintedAmount;
            } else {
                /* 
                Occurs only at extreme cases. 
                In this case, traders wins by a large margin and liquidation bot has little time to react. 
                IL has occured and pay back as much as possible to the supply pool while set borrowers collateral asset to 0. 
                */
                totalMintedAmount = 0;
            }

            address vaultRewardDistributor = strategy.vaultReward[ICreditManager(userBorrowed.creditManagers[i]).vault()];

            ICreditTokenStaker(creditTokenStaker).withdraw(vaultRewardDistributor, userBorrowed.borrowedMintedAmount[i]);
        }

        if (totalMintedAmount > 0) {
            collateralAmountOut = IDepositor(userLendCredit.depositor).withdraw(userLendCredit.token, totalMintedAmount, 0);

            if (_liquidator != address(0)) {
                uint256 liquidatorFee = (collateralAmountOut * LIQUIDATE_FEE) / LIQUIDATE_PRECISION;
                collateralAmountOut = collateralAmountOut - liquidatorFee;
                IERC20MetadataUpgradeable(userLendCredit.token).safeTransfer(_liquidator, liquidatorFee);

                emit LiquidatorFee(_liquidator, liquidatorFee, _borrowedIndex);
            }

            IERC20MetadataUpgradeable(userLendCredit.token).safeTransfer(_recipient, collateralAmountOut);
        }

        ICreditTokenStaker(creditTokenStaker).withdrawFor(strategy.collateralReward, _recipient, userBorrowed.collateralMintedAmount);
        ICreditUser(creditUser).destroy(_recipient, _borrowedIndex);

        emit RepayCredit(_recipient, _borrowedIndex, userLendCredit.token, collateralAmountOut, block.timestamp);

        return collateralAmountOut;
    }

    function _withdrawBorrowedAmount(
        address _depositor,
        address _borrowedTokens,
        uint256 _borrowedAmountOuts
    ) internal returns (uint256, uint256) {
        uint256 usedMintedAmount = _sellGlpFromAmount(_borrowedTokens, _borrowedAmountOuts);
        uint256 amountOut = IDepositor(_depositor).withdraw(_borrowedTokens, usedMintedAmount, 0);

        return (usedMintedAmount, amountOut);
    }

    /// @notice liquidate position
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    function liquidate(address _recipient, uint256 _borrowedIndex) external override nonReentrant {
        uint256 lastestIndex = ICreditUser(creditUser).getUserCounts(_recipient);

        require(_borrowedIndex > 0, "CreditCaller: Minimum limit exceeded");
        require(_borrowedIndex <= lastestIndex, "CreditCaller: Index out of range");

        bool isTerminated = ICreditUser(creditUser).isTerminated(_recipient, _borrowedIndex);
        bool isTimeout = ICreditUser(creditUser).isTimeout(_recipient, _borrowedIndex, MAX_LOAN_DURATION);

        require(!isTerminated, "CreditCaller: Already terminated");

        uint256 health = getUserCreditHealth(_recipient, _borrowedIndex);

        if (health <= LIQUIDATE_THRESHOLD || isTimeout) {
            _repayCredit(_recipient, _borrowedIndex, msg.sender);

            emit Liquidate(_recipient, _borrowedIndex, health, block.timestamp);
        }
    }

    /// @notice calculate health factor
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    function getUserCreditHealth(address _recipient, uint256 _borrowedIndex) public view returns (uint256) {
        (, , , address[] memory borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(_recipient, _borrowedIndex);
        (address[] memory creditManagers, uint256[] memory borrowedAmountOuts, uint256 collateralMintedAmount, , uint256 totalMintedAmount) = ICreditUser(
            creditUser
        ).getUserBorrowed(_recipient, _borrowedIndex);

        uint256 borrowedMinted;

        for (uint256 i = 0; i < creditManagers.length; i++) {
            borrowedMinted = borrowedMinted + _sellGlpFromAmount(borrowedTokens[i], borrowedAmountOuts[i]);
        }

        return calcHealth(totalMintedAmount, borrowedMinted, collateralMintedAmount);
    }

    /// @notice add strategy
    /// @param _depositor archi depositor address
    /// @param _collateralReward collateral reward pool
    /// @param _vaults supported vaults
    /// @param _vaultRewardDistributors vault reward pool distributor
    function addStrategy(
        address _depositor,
        address _collateralReward,
        address[] calldata _vaults,
        address[] calldata _vaultRewardDistributors
    ) external onlyOwner {
        require(_vaults.length == _vaultRewardDistributors.length, "CreditCaller: Length mismatch");
        require(_depositor != address(0), "CreditCaller: _depositor cannot be 0x0");
        require(_collateralReward != address(0), "CreditCaller: _collateralReward cannot be 0x0");

        Strategy storage strategy = strategies[_depositor];

        strategy.listed = true;
        strategy.collateralReward = _collateralReward;

        for (uint256 i = 0; i < _vaults.length; i++) {
            strategy.vaultReward[_vaults[i]] = _vaultRewardDistributors[i];
        }

        emit AddStrategy(_depositor, _collateralReward, _vaults, _vaultRewardDistributors);
    }

    /// @notice bond collateral token and manager
    /// @param _underlyingToken collateral token addresses
    /// @param _creditManager archi credit manager address
    function addVaultManager(address _underlyingToken, address _creditManager) external onlyOwner {
        require(_underlyingToken != address(0), "CreditCaller: _underlyingToken cannot be 0x0");
        require(_creditManager != address(0), "CreditCaller: _creditManager cannot be 0x0");
        require(vaultManagers[_underlyingToken] == address(0), "CreditCaller: Not allowed");

        vaultManagers[_underlyingToken] = _creditManager;

        emit AddVaultManager(_underlyingToken, _creditManager);
    }

    /// @notice set user info contract
    /// @param _creditUser contract address
    function setCreditUser(address _creditUser) external onlyOwner {
        require(_creditUser != address(0), "CreditCaller: _creditUser cannot be 0x0");
        require(creditUser == address(0), "CreditCaller: Cannot run this function twice");
        creditUser = _creditUser;

        emit SetCreditUser(_creditUser);
    }

    /// @notice set credit token staker
    /// @param _creditTokenStaker contract address
    function setCreditTokenStaker(address _creditTokenStaker) external onlyOwner {
        require(_creditTokenStaker != address(0), "CreditCaller: _creditTokenStaker cannot be 0x0");
        require(creditTokenStaker == address(0), "CreditCaller: Cannot run this function twice");
        creditTokenStaker = _creditTokenStaker;

        emit SetCreditTokenStaker(creditTokenStaker);
    }

    /// @notice set whitelist contract
    /// @param _allowlist contract address
    function setAllowlist(address _allowlist) external onlyOwner {
        allowlist = _allowlist;
    }

    /// @notice shortcut function helper, help user to claim fast
    /// @param _target target contract address
    /// @param _recipient user
    function claimFor(address _target, address _recipient) external nonReentrant {
        IClaim(_target).claim(_recipient);
    }

    /// @notice calculate borrow amount
    /// @param _collateralAmountIn amount of collateral token
    /// @param _collateralToken collateral token
    /// @param _ratio leverage ratio
    /// @param _borrowedToken borrowed token
    /// @return borrowed amount
    function _calcFormula(
        uint256 _collateralAmountIn,
        address _collateralToken,
        uint256 _ratio,
        address _borrowedToken
    ) internal view returns (uint256) {
        uint256 collateralPrice = _tokenPrice(_collateralToken);
        uint256 borrowedPrice = _tokenPrice(_borrowedToken);

        return (_collateralAmountIn * collateralPrice * _ratio) / borrowedPrice / RATIO_PRECISION;
    }

    /// @notice format _calcFormula precision
    /// @dev parameter refers to _calcFormula
    function calcBorrowAmount(
        uint256 _collateralAmountIn,
        address _collateralToken,
        uint256 _ratio,
        address _borrowedToken
    ) public view returns (uint256) {
        uint256 collateralDecimals = IERC20MetadataUpgradeable(_collateralToken).decimals();
        uint256 borrowedTokenDecimals = IERC20MetadataUpgradeable(_borrowedToken).decimals();

        return (_calcFormula(_collateralAmountIn, _collateralToken, _ratio, _borrowedToken) * 10**borrowedTokenDecimals) / 10**collateralDecimals;
    }

    /// @notice calculate health
    /// @param _totalAmounts user total amount of GLP
    /// @param _borrowedAmounts user borrowed amount of GLP
    /// @param _collateralAmounts user collateral amount of GLP
    /// @return retrun health factor
    function calcHealth(
        uint256 _totalAmounts,
        uint256 _borrowedAmounts,
        uint256 _collateralAmounts
    ) public pure returns (uint256) {
        if (_totalAmounts < _borrowedAmounts) return 0;

        return ((_totalAmounts - _borrowedAmounts) * LIQUIDATE_DENOMINATOR) / _collateralAmounts;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20MetadataUpgradeable(_token).safeApprove(_spender, 0);
        IERC20MetadataUpgradeable(_token).safeApprove(_spender, _amount);
    }

    function _requireValidRatio(uint256[] memory _ratios) internal pure {
        require(_ratios.length > 0, "CreditCaller: _ratios cannot be empty");

        uint256 total;

        for (uint256 i = 0; i < _ratios.length; i++) total = total + _ratios[i];

        require(total <= MAX_RATIO, "CreditCaller: MAX_RATIO limit exceeded");
        require(total >= MIN_RATIO, "CreditCaller: MIN_RATIO limit exceeded");
    }

    /// @notice get token prices
    /// @param _token collateral token
    /// @return prices
    function _tokenPrice(address _token) internal view returns (uint256) {
        address aggregator = IAddressProvider(addressProvider).getCreditAggregator();

        return ICreditAggregator(aggregator).getTokenPrice(_token);
    }

    /// @notice calculate required GLP for amountIn
    /// @param _swapToken token address
    /// @param _amountIn token amount
    /// @return glp GLP amount
    function _sellGlpFromAmount(address _swapToken, uint256 _amountIn) internal view returns (uint256) {
        address aggregator = IAddressProvider(addressProvider).getCreditAggregator();

        (uint256 amountOut, ) = ICreditAggregator(aggregator).getSellGlpFromAmount(_swapToken, _amountIn);

        return amountOut;
    }

    /// @notice wrapped ETH
    /// @param _amountIn ETH amount
    function _wrapETH(uint256 _amountIn) internal {
        require(msg.value == _amountIn, "CreditCaller: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("CreditCaller: Not allowed");
    }
}
