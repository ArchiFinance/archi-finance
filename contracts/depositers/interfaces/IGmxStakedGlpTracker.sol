// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGmxStakedGlpTracker {
    function unstake(address _depositToken, uint256 _amount) external;

    function stake(address _depositToken, uint256 _amount) external;
}
