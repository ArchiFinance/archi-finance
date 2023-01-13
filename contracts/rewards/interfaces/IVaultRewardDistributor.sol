// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultRewardDistributor {
    function stake(uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external returns (uint256);

    event SetSupplyRewardPoolRatio(uint256 _ratio);
    event SetBorrowedRewardPoolRatio(uint256 _ratio);
    event Stake(uint256 _amountIn);
    event Withdraw(uint256 _amountOut);
    event Distribute(uint256 _rewards);
}
