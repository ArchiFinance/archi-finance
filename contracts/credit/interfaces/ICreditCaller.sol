// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditCaller {
    event LendCreditGLP(
        address indexed _recipient,
        address _depositer,
        address _targetToken,
        uint256 _glpAmountIn,
        address[] _borrowedTokens,
        uint256[] _ratios
    );
    event LendCredit(address indexed _recipient, address _depositer, address _token, uint256 _amountIn, address[] _borrowedTokens, uint256[] _ratios);
    event RepayCredit(address indexed _recipient, uint256 _borrowedIndex, uint256 _collateralAmountOut);
    event Liquidate(address _recipient, uint256 _borrowedIndex,uint256 _health);
    event AddStrategy(address _depositer, address _collateralReward, address[] _vaults, address[] _vaultRewards);
    event AddVaultManager(address _underlying, address _creditManager);
    event SetCreditUser(address _creditUser);
    event SetCreditToken(address _creditToken);
}
