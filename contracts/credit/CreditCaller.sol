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
    uint256 private constant MAX_LIQUIDATE_THRESHOLD = 500; // 50%
    uint256 private constant MIN_LIQUIDATE_THRESHOLD = 300; // 30%
    uint256 private constant MAX_LIQUIDATOR_FEE = 200; // 20%
    uint256 private constant MIN_LIQUIDATOR_FEE = 50; // 5%
    uint256 private constant LIQUIDATE_PRECISION = 1000;
    uint256 private constant LIQUIDATOR_FEE_PRECISION = 1000;
    uint256 private constant MAX_LOAN_DURATION = 1 days * 365;
    uint256 private constant NEXT_LOAN_PERIOD = 2 days;

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

    uint256 public liquidateThreshold;
    uint256 public liquidatorFee;

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
        liquidateThreshold = 400; // 40%
        liquidatorFee = 100; // 10%
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

        // Check if the user has used the authority to call the function.
        {
            bool passed;

            if (allowlist != address(0)) {
                passed = IAllowlist(allowlist).can(_recipient);

                require(passed, "CreditCaller: Not whitelisted");
            }

            passed = ICreditUser(creditUser).hasPassedSinceLastTerminated(_recipient, NEXT_LOAN_PERIOD);

            require(passed, "CreditCaller: The next loan period is invalid");
        }

        if (_token == ZERO) {
            _wrapETH(_amountIn);

            _token = wethAddress;
        } else {
            uint256 before = IERC20MetadataUpgradeable(_token).balanceOf(address(this));
            IERC20MetadataUpgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20MetadataUpgradeable(_token).balanceOf(address(this)) - before;
        }

        require(vaultManagers[_token] != address(0), "CreditCaller: The collateral asset must be one of the borrow tokens");

        uint256 reservedLiquidatorFee = (_amountIn * liquidatorFee) / LIQUIDATOR_FEE_PRECISION;

        IERC20MetadataUpgradeable(_token).safeTransfer(creditUser, reservedLiquidatorFee);

        _amountIn = _amountIn - reservedLiquidatorFee;

        ICreditUser.UserLendCredit memory userLendCredit;

        userLendCredit.depositor = _depositor;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.reservedLiquidatorFee = reservedLiquidatorFee;
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
            _userLendCredit.reservedLiquidatorFee,
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

        bool isTimeout = ICreditUser(creditUser).isTimeout(msg.sender, _borrowedIndex, MAX_LOAN_DURATION);
        require(!isTimeout, "CreditCaller: Already timeout");

        return _repayCredit(msg.sender, _borrowedIndex, address(0));
    }

    function _repayCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _liquidator
    ) internal returns (uint256 collateralAmountOut) {
        ICreditUser.UserLendCredit memory userLendCredit;
        ICreditUser.UserBorrowed memory userBorrowed;

        (userLendCredit.depositor, userLendCredit.token, , , userLendCredit.borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(
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

        address aggregator = IAddressProvider(addressProvider).getCreditAggregator();

        (uint256 totalRepayMintedAmounts, uint256[] memory repayMintedAmounts) = ICreditAggregator(aggregator).getSellGlpFromAmounts(
            userLendCredit.borrowedTokens,
            userBorrowed.borrowedAmountOuts
        );

        if (_liquidator == address(0)) {
            if (totalMintedAmount < totalRepayMintedAmounts) {
                revert("CreditCaller: The current position needs to be liquidated");
            } else {
                for (uint256 i = 0; i < userBorrowed.creditManagers.length; i++) {
                    uint256 borrowedAmountOut = IDepositor(userLendCredit.depositor).withdraw(userLendCredit.borrowedTokens[i], repayMintedAmounts[i], 0);

                    require(borrowedAmountOut >= userBorrowed.borrowedAmountOuts[i], "CreditCaller: Insufficient balance");

                    _approve(userLendCredit.borrowedTokens[i], userBorrowed.creditManagers[i], userBorrowed.borrowedAmountOuts[i]);

                    ICreditManager(userBorrowed.creditManagers[i]).repay(_recipient, userBorrowed.borrowedAmountOuts[i], 0, false);

                    address vaultRewardDistributor = strategy.vaultReward[ICreditManager(userBorrowed.creditManagers[i]).vault()];

                    ICreditTokenStaker(creditTokenStaker).withdraw(vaultRewardDistributor, userBorrowed.borrowedMintedAmount[i]);

                    totalMintedAmount = totalMintedAmount - repayMintedAmounts[i];
                }
            }
        } else {
            for (uint256 i = 0; i < userBorrowed.creditManagers.length; i++) {
                address vaultRewardDistributor = strategy.vaultReward[ICreditManager(userBorrowed.creditManagers[i]).vault()];

                ICreditTokenStaker(creditTokenStaker).withdraw(vaultRewardDistributor, userBorrowed.borrowedMintedAmount[i]);

                if (totalMintedAmount == 0) {
                    ICreditManager(userBorrowed.creditManagers[i]).repay(_recipient, userBorrowed.borrowedAmountOuts[i], 0, true);
                    continue;
                }

                uint256 repayAmountDuringLiquidation;

                if (repayMintedAmounts[i] >= totalMintedAmount) {
                    repayAmountDuringLiquidation = IDepositor(userLendCredit.depositor).withdraw(userLendCredit.borrowedTokens[i], totalMintedAmount, 0);
                    totalMintedAmount = 0;
                } else {
                    repayAmountDuringLiquidation = IDepositor(userLendCredit.depositor).withdraw(userLendCredit.borrowedTokens[i], repayMintedAmounts[i], 0);
                    totalMintedAmount = totalMintedAmount - repayMintedAmounts[i];
                }

                _approve(userLendCredit.borrowedTokens[i], userBorrowed.creditManagers[i], repayAmountDuringLiquidation);
                ICreditManager(userBorrowed.creditManagers[i]).repay(_recipient, userBorrowed.borrowedAmountOuts[i], repayAmountDuringLiquidation, true);
            }

            emit LiquidatorFee(_liquidator, userLendCredit.reservedLiquidatorFee, _borrowedIndex);
        }

        if (totalMintedAmount > 0) {
            collateralAmountOut = IDepositor(userLendCredit.depositor).withdraw(userLendCredit.token, totalMintedAmount, 0);

            IERC20MetadataUpgradeable(userLendCredit.token).safeTransfer(_recipient, collateralAmountOut);
        }

        ICreditTokenStaker(creditTokenStaker).withdrawFor(strategy.collateralReward, _recipient, userBorrowed.collateralMintedAmount);
        ICreditUser(creditUser).destroy(_recipient, _borrowedIndex, _liquidator);

        emit RepayCredit(_recipient, _borrowedIndex, userLendCredit.token, collateralAmountOut, block.timestamp);

        return collateralAmountOut;
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

        if (health <= liquidateThreshold || isTimeout) {
            _repayCredit(_recipient, _borrowedIndex, msg.sender);

            emit Liquidate(_recipient, _borrowedIndex, health, block.timestamp);
        }
    }

    /// @notice calculate health factor
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    function getUserCreditHealth(address _recipient, uint256 _borrowedIndex) public view returns (uint256) {
        (, , , , address[] memory borrowedTokens, ) = ICreditUser(creditUser).getUserLendCredit(_recipient, _borrowedIndex);
        (, uint256[] memory borrowedAmountOuts, uint256 collateralMintedAmount, , uint256 totalMintedAmount) = ICreditUser(creditUser).getUserBorrowed(
            _recipient,
            _borrowedIndex
        );

        address aggregator = IAddressProvider(addressProvider).getCreditAggregator();
        (uint256 totalRepayMintedAmounts, ) = ICreditAggregator(aggregator).getSellGlpFromAmounts(borrowedTokens, borrowedAmountOuts);

        return calcHealth(totalMintedAmount, totalRepayMintedAmounts, collateralMintedAmount);
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

    /// @notice Set the threshold for liquidation
    function setLiquidateThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold <= MAX_LIQUIDATE_THRESHOLD, "CreditCaller: MAX_LIQUIDATE_THRESHOLD limit exceeded");
        require(_threshold >= MIN_LIQUIDATE_THRESHOLD, "CreditCaller: MIN_LIQUIDATE_THRESHOLD limit exceeded");

        liquidateThreshold = _threshold;

        emit SetLiquidateThreshold(_threshold);
    }

    /// @notice Set the threshold for liquidation
    function setLiquidatorFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_LIQUIDATOR_FEE, "CreditCaller: MAX_LIQUIDATOR_FEE limit exceeded");
        require(_fee >= MIN_LIQUIDATOR_FEE, "CreditCaller: MIN_LIQUIDATOR_FEE limit exceeded");

        liquidatorFee = _fee;

        emit SetLiquidatorFee(_fee);
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

        return ((_totalAmounts - _borrowedAmounts) * LIQUIDATE_PRECISION) / _collateralAmounts;
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
