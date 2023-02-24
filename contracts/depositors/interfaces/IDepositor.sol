// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IDepositor {
    function mint(address _token, uint256 _amountIn) external payable returns (address, uint256);

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) external payable returns (uint256);

    function harvest() external returns (uint256);

    event Mint(address _token, uint256 _amountIn, uint256 _amountOut);
    event Withdraw(address _token, uint256 _amountIn, uint256 _amountOut);
    event Harvest(address _rewardToken, uint256 _rewards, uint256 _fees);
}
