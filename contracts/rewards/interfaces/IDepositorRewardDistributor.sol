// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IDepositorRewardDistributor {
    function distribute(uint256 _rewards) external;

    event AddExtraReward(address _reward);
    event ClearExtraRewards();
    event NewDistributor(address indexed _sender, address _distributor);
    event RemoveDistributor(address indexed _sender, address _distributor);
    event Distribute(address _reward, uint256 _rewards);
}
