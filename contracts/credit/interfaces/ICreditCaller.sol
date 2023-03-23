// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICreditCaller {
    function openLendCredit(
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable;

    function repayCredit(uint256 _borrowedIndex) external returns (uint256);

    function liquidate(address _recipient, uint256 _borrowedIndex) external;

    event LendCredit(
        address indexed _recipient,
        uint256 _borrowedIndex,
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] _borrowedTokens,
        uint256[] _ratios,
        uint256 _timestamp
    );
    event CalcBorrowAmount(address indexed _borrowedToken, uint256 _borrowedIndex, uint256 _borrowedAmountOuts, uint256 _borrowedMintedAmount);
    event RepayCredit(address indexed _recipient, uint256 _borrowedIndex, address _collateralToken, uint256 _collateralAmountOut, uint256 _timestamp);
    event RepayDebts(address indexed _recipient, uint256 _borrowedIndex, uint256 _amountOut, uint256 _borrowedAmountOut);
    event Liquidate(address _recipient, uint256 _borrowedIndex, uint256 _health, uint256 _timestamp);
    event LiquidatorFee(address _liquidator, uint256 _fee, uint256 _borrowedIndex);
    event AddStrategy(address _depositor, address _collateralReward, address[] _vaults, address[] _vaultRewards);
    event AddVaultManager(address _underlying, address _creditManager);
    event SetCreditUser(address _creditUser);
    event SetCreditTokenStaker(address _creditTokenStaker);
    event SetLiquidateThreshold(uint256 _threshold);
    event SetLiquidatorFee(uint256 _fee);
}
