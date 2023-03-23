// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { ICreditUser } from "./interfaces/ICreditUser.sol";

/* 
CreditUser is mainly used to record user's loan information, 
and only provides query methods to the public.
Interaction requires CreditCaller to call it.
*/

contract CreditUser is Initializable, ReentrancyGuardUpgradeable, ICreditUser {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public caller;
    uint256 public lendCreditIndex;

    mapping(address => uint256) internal creditCounts;
    mapping(uint256 => address) internal creditUsers;
    mapping(address => mapping(uint256 => UserLendCredit)) internal userLendCredits;
    mapping(address => mapping(uint256 => UserBorrowed)) internal userBorroweds;
    mapping(address => uint256) internal userLastTerminated;

    modifier onlyCaller() {
        require(caller == msg.sender, "CreditUser: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _caller) external initializer {
        __ReentrancyGuard_init();

        caller = _caller;
    }

    /// @notice update position index
    /// @param _recipient borrower
    function accrueSnapshot(address _recipient) external override onlyCaller returns (uint256) {
        require(_recipient != address(0), "CreditUser: _recipient cannot be 0x0");

        lendCreditIndex++;
        creditCounts[_recipient]++;
        creditUsers[lendCreditIndex] = _recipient;

        return creditCounts[_recipient];
    }

    /// @notice store requrest leverage info
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @param _depositor archi depositor
    /// @param _token collateral token
    /// @param _amountIn collateral amount
    /// @param _borrowedTokens borrowed tokens
    /// @param _ratios leverage ratio
    function createUserLendCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _depositor,
        address _token,
        uint256 _amountIn,
        uint256 _reservedLiquidatorFee,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) external override onlyCaller {
        UserLendCredit memory userLendCredit;

        userLendCredit.depositor = _depositor;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.reservedLiquidatorFee = _reservedLiquidatorFee;
        userLendCredit.borrowedTokens = _borrowedTokens;
        userLendCredit.ratios = _ratios;

        userLendCredits[_recipient][_borrowedIndex] = userLendCredit;

        emit CreateUserLendCredit(_recipient, _borrowedIndex, _depositor, _token, _amountIn, _borrowedTokens, _ratios);
    }

    /// @notice store user leverage info
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @param _creditManagers vault manager
    /// @param _borrowedAmountOuts borrowed amount
    /// @param _collateralMintedAmount collateral amount in GLP
    /// @param _borrowedMintedAmount borrowed amount in GLP
    function createUserBorrowed(
        address _recipient,
        uint256 _borrowedIndex,
        address[] calldata _creditManagers,
        uint256[] calldata _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] calldata _borrowedMintedAmount
    ) external override onlyCaller {
        UserBorrowed memory userBorrowed;

        userBorrowed.creditManagers = _creditManagers;
        userBorrowed.borrowedAmountOuts = _borrowedAmountOuts;
        userBorrowed.collateralMintedAmount = _collateralMintedAmount;
        userBorrowed.borrowedMintedAmount = _borrowedMintedAmount;
        userBorrowed.borrowedAt = block.timestamp;

        userBorroweds[_recipient][_borrowedIndex] = userBorrowed;

        emit CreateUserBorrowed(
            _recipient,
            _borrowedIndex,
            _creditManagers,
            _borrowedAmountOuts,
            _collateralMintedAmount,
            _borrowedMintedAmount,
            userBorrowed.borrowedAt
        );
    }

    /// @notice terminate a leverage
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    function destroy(
        address _recipient,
        uint256 _borrowedIndex,
        address _liquidator
    ) external override onlyCaller {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        userLendCredit.terminated = true;

        userLastTerminated[_recipient] = block.timestamp;

        if (userLendCredit.reservedLiquidatorFee > 0) {
            if (_liquidator == address(0)) {
                IERC20Upgradeable(userLendCredit.token).safeTransfer(_recipient, userLendCredit.reservedLiquidatorFee);
            } else {
                IERC20Upgradeable(userLendCredit.token).safeTransfer(_liquidator, userLendCredit.reservedLiquidatorFee);
            }
        }

        emit Destroy(_recipient, _borrowedIndex);
    }

     /// @notice determine the end time of the previous leverage
    /// @param _recipient borrower
    /// @param _duration position index
    /// @return bool value
    function hasPassedSinceLastTerminated(address _recipient, uint256 _duration) external view override returns (bool) {
        return block.timestamp - userLastTerminated[_recipient] > _duration;
    }

    /// @notice if leverage is terminated
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @return bool value
    function isTerminated(address _recipient, uint256 _borrowedIndex) external view override returns (bool) {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];
        return userLendCredit.terminated;
    }

    /// @notice if leverage is overdue
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @param _duration maximum repay time
    /// @return bool value
    function isTimeout(
        address _recipient,
        uint256 _borrowedIndex,
        uint256 _duration
    ) external view override returns (bool) {
        UserBorrowed storage userBorrowed = userBorroweds[_recipient][_borrowedIndex];
        return block.timestamp - userBorrowed.borrowedAt > _duration;
    }

    /// @notice get open leverage info
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @return depositor archi depositor
    /// @return token collateral token
    /// @return amountIn collateral amount
    /// @return reservedLiquidatorFee retain liquidator fees, which will be refunded if not incurred
    /// @return borrowedTokens borrowed tokens
    /// @return ratios leverage ratio
    function getUserLendCredit(address _recipient, uint256 _borrowedIndex)
        external
        view
        override
        returns (
            address depositor,
            address token,
            uint256 amountIn,
            uint256 reservedLiquidatorFee,
            address[] memory borrowedTokens,
            uint256[] memory ratios
        )
    {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        depositor = userLendCredit.depositor;
        token = userLendCredit.token;
        amountIn = userLendCredit.amountIn;
        reservedLiquidatorFee = userLendCredit.reservedLiquidatorFee;
        borrowedTokens = userLendCredit.borrowedTokens;
        ratios = userLendCredit.ratios;
    }

    /// @notice get leverage info
    /// @param _recipient borrower
    /// @param _borrowedIndex position index
    /// @return creditManagers vault manager
    /// @return borrowedAmountOuts borrowed amount
    /// @return collateralMintedAmount collateral amount in GLP
    /// @return borrowedMintedAmount borrowed amount in GLP
    function getUserBorrowed(address _recipient, uint256 _borrowedIndex)
        external
        view
        override
        returns (
            address[] memory creditManagers,
            uint256[] memory borrowedAmountOuts,
            uint256 collateralMintedAmount,
            uint256[] memory borrowedMintedAmount,
            uint256 mintedAmount
        )
    {
        UserBorrowed storage userBorrowed = userBorroweds[_recipient][_borrowedIndex];

        for (uint256 i = 0; i < userBorrowed.borrowedMintedAmount.length; i++) {
            mintedAmount = mintedAmount + userBorrowed.borrowedMintedAmount[i];
        }

        mintedAmount = mintedAmount + userBorrowed.collateralMintedAmount;

        creditManagers = userBorrowed.creditManagers;
        borrowedAmountOuts = userBorrowed.borrowedAmountOuts;
        collateralMintedAmount = userBorrowed.collateralMintedAmount;
        borrowedMintedAmount = userBorrowed.borrowedMintedAmount;
    }

    /// @notice number of leverage
    /// @param _recipient borrower
    function getUserCounts(address _recipient) external view override returns (uint256) {
        return creditCounts[_recipient];
    }

    /// @notice get borrower from global borrow index
    /// @param _borrowedIndex position index
    function getLendCreditUsers(uint256 _borrowedIndex) external view override returns (address) {
        return creditUsers[_borrowedIndex];
    }
}
