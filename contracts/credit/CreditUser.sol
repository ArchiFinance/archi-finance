// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import { ICreditUser } from "./interfaces/ICreditUser.sol";

contract CreditUser is Initializable, ReentrancyGuardUpgradeable, ICreditUser {
    using SafeMathUpgradeable for uint256;

    struct UserLendCredit {
        address depositer;
        address token;
        uint256 amountIn;
        address[] borrowedTokens;
        uint256[] ratios;
        bool terminated;
    }

    struct UserBorrowed {
        address[] creditManagers;
        uint256[] borrowedAmountOuts;
        uint256 collateralMintedAmount;
        uint256[] borrowedMintedAmount;
    }

    address public caller;

    uint256 public lendCreditIndex;

    mapping(address => uint256) internal creditCounts;
    mapping(address => mapping(uint256 => UserLendCredit)) internal userLendCredits;
    mapping(address => mapping(uint256 => UserBorrowed)) internal userBorroweds;
    mapping(uint256 => address) internal lendCreditsUsers;

    modifier onlyCaller() {
        require(caller == msg.sender, "CreditUser: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function initialize(address _caller) external initializer {
        __ReentrancyGuard_init();

        caller = _caller;
    }

    function accrueSnapshot(address _recipient) external override onlyCaller returns (uint256) {
        lendCreditIndex++;
        lendCreditsUsers[lendCreditIndex] = _recipient;
        creditCounts[_recipient]++;

        return creditCounts[_recipient];
    }

    function createUserLendCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) external override onlyCaller {
        UserLendCredit memory userLendCredit;

        userLendCredit.depositer = _depositer;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.borrowedTokens = _borrowedTokens;
        userLendCredit.ratios = _ratios;

        userLendCredits[_recipient][_borrowedIndex] = userLendCredit;

        emit CreateUserLendCredit(_recipient, _borrowedIndex, _depositer, _token, _amountIn, _borrowedTokens, _ratios);
    }

    function createUserBorroweds(
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

        userBorroweds[_recipient][_borrowedIndex] = userBorrowed;

        emit CreateUserBorroweds(_recipient, _borrowedIndex, _creditManagers, _borrowedAmountOuts, _collateralMintedAmount, _borrowedMintedAmount);
    }

    function destroy(address _recipient, uint256 _borrowedIndex) external override onlyCaller {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        userLendCredit.terminated = true;

        emit Destroy(_recipient, _borrowedIndex);
    }

    function isTerminated(address _recipient, uint256 _borrowedIndex) external view override returns (bool) {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];
        return userLendCredit.terminated;
    }

    function getUserLendCredit(address _recipient, uint256 _borrowedIndex)
        external
        view
        override
        returns (
            address depositer,
            address token,
            uint256 amountIn,
            address[] memory borrowedTokens,
            uint256[] memory ratios
        )
    {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        depositer = userLendCredit.depositer;
        token = userLendCredit.token;
        amountIn = userLendCredit.amountIn;
        borrowedTokens = userLendCredit.borrowedTokens;
        ratios = userLendCredit.ratios;
    }

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
            mintedAmount = mintedAmount.add(userBorrowed.borrowedMintedAmount[i]);
        }

        mintedAmount = mintedAmount.add(userBorrowed.collateralMintedAmount);

        creditManagers = userBorrowed.creditManagers;
        borrowedAmountOuts = userBorrowed.borrowedAmountOuts;
        collateralMintedAmount = userBorrowed.collateralMintedAmount;
        borrowedMintedAmount = userBorrowed.borrowedMintedAmount;
    }

    function getUserCounts(address _recipient) external view override returns (uint256) {
        return creditCounts[_recipient];
    }

    function getLendCreditsUsers(uint256 _borrowedIndex) external view override returns (address) {
        return lendCreditsUsers[_borrowedIndex];
    }
}
