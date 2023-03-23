// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICreditUser {
    struct UserLendCredit {
        address depositor;
        address token;
        uint256 amountIn;
        uint256 reservedLiquidatorFee;
        address[] borrowedTokens;
        uint256[] ratios;
        bool terminated;
    }

    struct UserBorrowed {
        address[] creditManagers;
        uint256[] borrowedAmountOuts;
        uint256 collateralMintedAmount;
        uint256[] borrowedMintedAmount;
        uint256 borrowedAt;
    }

    function accrueSnapshot(address _recipient) external returns (uint256);

    function createUserLendCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _depositor,
        address _token,
        uint256 _amountIn,
        uint256 _reservedLiquidatorFee,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) external;

    function createUserBorrowed(
        address _recipient,
        uint256 _borrowedIndex,
        address[] calldata _creditManagers,
        uint256[] calldata _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] calldata _borrowedMintedAmount
    ) external;

    function destroy(
        address _recipient,
        uint256 _borrowedIndex,
        address _liquidator
    ) external;

    function hasPassedSinceLastTerminated(address _recipient, uint256 _duration) external view returns (bool);

    function isTerminated(address _recipient, uint256 _borrowedIndex) external view returns (bool);

    function isTimeout(
        address _recipient,
        uint256 _borrowedIndex,
        uint256 _duration
    ) external view returns (bool);

    function getUserLendCredit(address _recipient, uint256 _borrowedIndex)
        external
        view
        returns (
            address depositor,
            address token,
            uint256 amountIn,
            uint256 _reservedLiquidatorFee,
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

    function getLendCreditUsers(uint256 _borrowedIndex) external view returns (address);

    event CreateUserLendCredit(
        address indexed _recipient,
        uint256 _borrowedIndex,
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] _borrowedTokens,
        uint256[] _ratios
    );

    event CreateUserBorrowed(
        address indexed _recipient,
        uint256 _borrowedIndex,
        address[] _creditManagers,
        uint256[] _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] _borrowedMintedAmount,
        uint256 _borrowedAt
    );

    event Destroy(address indexed _recipient, uint256 _borrowedIndex);
}
