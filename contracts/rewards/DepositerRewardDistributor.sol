// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IAbstractReward } from "./interfaces/IAbstractReward.sol";
import { IDepositerRewardDistributor } from "./interfaces/IDepositerRewardDistributor.sol";

contract DepositerRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IDepositerRewardDistributor {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1e18;

    address public stakingToken;
    address public rewardToken;
    address[] public extraRewards;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _rewardToken, address _stakingToken) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
    }

    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    function addExtraReward(address _reward) external onlyOwner returns (bool) {
        require(_reward != address(0), "DepositerRewardDistributor: Address cannot be 0");
        require(IAbstractReward(_reward).stakingToken() == stakingToken, "DepositerRewardDistributor: Mismatched staking token");
        require(IAbstractReward(_reward).rewardToken() == rewardToken, "DepositerRewardDistributor: Mismatched reward token");

        extraRewards.push(_reward);

        emit AddExtraReward(_reward);

        return true;
    }

    function clearExtraRewards() external onlyOwner {
        delete extraRewards;

        emit ClearExtraRewards();
    }

    function distribute(uint256 _rewards) external override nonReentrant {
        require(_rewards < type(uint256).max, "DepositerRewardDistributor: Maximum limit exceeded");

        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

            for (uint256 i = 0; i < extraRewards.length; i++) {
                uint256 totalSupply = IERC20Upgradeable(stakingToken).totalSupply();
                uint256 balance = IERC20Upgradeable(stakingToken).balanceOf(extraRewards[i]);
                uint256 ratio = balance.mul(PRECISION).div(totalSupply);
                uint256 amounts = _rewards.mul(ratio).div(PRECISION);
    
                _approve(rewardToken, extraRewards[i], amounts);

                IAbstractReward(extraRewards[i]).distribute(amounts);

                emit Distribute(extraRewards[i], _rewards);
            }
        }
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}
