// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICreditTokenStaker {
    function creditToken() external view returns (address);

    function stake(address _vaultRewardDistributor, uint256 _amountIn) external returns (bool);

    function withdraw(address _vaultRewardDistributor, uint256 _amountOut) external returns (bool);

    function stakeFor(
        address _collateralReward,
        address _recipient,
        uint256 _amountIn
    ) external returns (bool);

    function withdrawFor(
        address _collateralReward,
        address _recipient,
        uint256 _amountOut
    ) external returns (bool);

    event NewOwner(address indexed _sender, address _owner);
    event RemoveOwner(address indexed _sender, address _owner);
    event Stake(address indexed _owner, address _vaultRewardDistributor, uint256 _amountIn);
    event Withdraw(address indexed _owner, address _vaultRewardDistributor, uint256 _amountOut);
    event StakeFor(address indexed _owner, address _collateralReward, address _recipient, uint256 _amountIn);
    event WithdrawFor(address indexed _owner, address _collateralReward, address _recipient, uint256 _amountOut);
    event SetCreditToken(address _creditToken);
}
