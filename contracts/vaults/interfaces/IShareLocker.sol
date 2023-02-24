// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IShareLocker {
    function rewardPool() external view returns (address);

    function harvest() external returns (uint256 claimed);

    function stake(uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external;
}
