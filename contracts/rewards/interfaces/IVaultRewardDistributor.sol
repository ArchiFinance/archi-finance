// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { ICommonReward } from "./ICommonReward.sol";

interface IVaultRewardDistributor is ICommonReward {
    function stake(uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external returns (uint256);

    event SetSupplyRewardPoolRatio(uint256 _ratio);
    event SetBorrowedRewardPoolRatio(uint256 _ratio);
    event SetSupplyRewardPool(address _rewardPool);
    event SetBorrowedRewardPool(address _rewardPool);
    event Stake(uint256 _amountIn);
    event Withdraw(uint256 _amountOut);
}
