// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IShareLocker {
    function borrow(uint256 _borrowedAmount) external returns (uint256);

    function repay(uint256 _borrowedAmount) external;

    function price() external view returns (uint256);

    function rewardPool() external view returns (address);

    function underlyingToken() external view returns (address);

    function claim() external returns (uint256 claimed);
}
