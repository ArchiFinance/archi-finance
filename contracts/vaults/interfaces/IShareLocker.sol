// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IShareLocker {
    function rewardPool() external view returns (address);

    function harvest() external returns (uint256 claimed);
}
