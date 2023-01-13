// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAbstractReward {
    function stakeFor(address _recipient, uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external returns (uint256);

    function claim() external returns (uint256 claimed);

    function pendingRewards(address _for) external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function distribute(uint256 _rewards) external returns (uint256);

    event StakeFor(address indexed _recipient, uint256 _amountIn, uint256 _totalSupply, uint256 _totalUnderlying);
    event Withdraw(address indexed _recipient, uint256 _amountOut, uint256 _totalSupply, uint256 _totalUnderlying);
    event Claim(address indexed _recipient, uint256 _claimed);
    event Distribute(uint256 _rewards, uint256 _accRewardPerShare);
}
