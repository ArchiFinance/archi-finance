// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICommonReward {
    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function distribute(uint256 _rewards) external;

    event Distribute(uint256 _rewards, uint256 _accRewardPerShare);
}
