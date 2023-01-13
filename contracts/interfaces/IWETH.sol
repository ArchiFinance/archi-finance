// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function depositTo(address account) external payable;

    function withdrawTo(address account, uint256 amount) external;
}
