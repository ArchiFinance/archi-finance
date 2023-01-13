// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDepositerRewardDistributor {
    function distribute(uint256 _rewards) external;

    event AddExtraReward(address _reward);
    event ClearExtraRewards();
    event Distribute(address _reward, uint256 _rewards);
}
