// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardTracker {
    function rewardToken() external view returns (address);

    function tokensPerInterval() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);
}
