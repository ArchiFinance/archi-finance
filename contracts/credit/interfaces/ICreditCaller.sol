// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditCaller {
    function openLendCredit(
        address _depositer,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable;

    function repayCredit(uint256 _borrowedIndex) external returns (uint256);

    function liquidate(address _recipient, uint256 _borrowedIndex) external;

    event LendCredit(address indexed _recipient, address _depositer, address _token, uint256 _amountIn, address[] _borrowedTokens, uint256[] _ratios);
    event CalcBorrowAmount(address _borrowedToken, uint256 _borrowedAmountOuts, uint256 _borrowedMintedAmount);
    event RepayCredit(address indexed _recipient, uint256 _borrowedIndex, uint256 _collateralAmountOut);
    event Liquidate(address _recipient, uint256 _borrowedIndex, uint256 _health);
    event AddStrategy(address _depositer, address _collateralReward, address[] _vaults, address[] _vaultRewards);
    event AddVaultManager(address _underlying, address _creditManager);
    event SetCreditUser(address _creditUser);
    event SetCreditToken(address _creditToken);
    event SetTokenDecimals(address _underlyingToken, uint256 _decimals);
}
