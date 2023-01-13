// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWETHZap {
    function zap(address _fromToken, uint256 _amountIn) external payable returns (uint256);
}
