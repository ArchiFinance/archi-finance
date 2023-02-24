// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IAllowlist {
    function can(address _account) external view returns (bool);
}
