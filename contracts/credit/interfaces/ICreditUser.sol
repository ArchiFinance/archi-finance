// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditUser {
    function accrueSnapshot(address _recipient) external returns (uint256);

    function createUserLendCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) external;

    function createUserBorroweds(
        address _recipient,
        uint256 _borrowedIndex,
        address[] calldata _creditManagers,
        uint256[] calldata _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] calldata _borrowedMintedAmount
    ) external;

    function destroy(address _recipient, uint256 _borrowedIndex) external;

    function isTerminated(address _user, uint256 _borrowedIndex) external view returns (bool);

    function getUserLendCredit(address _user, uint256 _borrowedIndex)
        external
        view
        returns (
            address depositer,
            address token,
            uint256 amountIn,
            address[] memory borrowedTokens,
            uint256[] memory ratio
        );

    function getUserBorrowed(address _user, uint256 _borrowedIndex)
        external
        view
        returns (
            address[] memory creditManagers,
            uint256[] memory borrowedAmountOuts,
            uint256 collateralMintedAmount,
            uint256[] memory borrowedMintedAmount,
            uint256 mintedAmount
        );

    function getUserCounts(address _recipient) external view returns (uint256);

    function getLendCreditsUsers(uint256 _borrowedIndex) external view returns (address);

    event CreateUserLendCredit(
        address indexed _recipient,
        uint256 _borrowedIndex,
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] _borrowedTokens,
        uint256[] _ratios
    );

    event CreateUserBorroweds(
        address indexed _recipient,
        uint256 _borrowedIndex,
        address[] _creditManagers,
        uint256[] _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] _borrowedMintedAmount
    );

    event Destroy(address indexed _recipient, uint256 _borrowedIndex);
}
