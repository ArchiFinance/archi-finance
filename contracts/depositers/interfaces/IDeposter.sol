// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDeposter {
    function mint(address _token, uint256 _amountIn) external payable returns (address, uint256);

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) external payable returns (uint256);

    event Mint(address _token, uint256 _amountIn, uint256 _amountOut);
    event Withdraw(address _token, uint256 _amountIn, uint256 _amountOut);
    event Harvest(uint256 _rewards);
}
