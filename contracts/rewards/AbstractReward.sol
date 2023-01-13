// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IAbstractReward } from "./interfaces/IAbstractReward.sol";

abstract contract AbstractReward is Initializable, ReentrancyGuardUpgradeable, IAbstractReward {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1e18;

    struct User {
        uint256 totalUnderlying;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    address public override stakingToken;
    address public override rewardToken;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;

    mapping(address => User) public users;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function __initial(address _stakingToken, address _rewardToken) internal {
        __ReentrancyGuard_init();

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
    }

    /** @dev this function is defined in a child contract */
    function stakeFor(address _recipient, uint256 _amountIn) external virtual override;

    function withdraw(uint256 _amountOut) external virtual override returns (uint256);

    function _updateRewards(address _for) internal {
        User storage user = users[_for];

        uint256 rewards = _checkPoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    function claim() external override nonReentrant returns (uint256 claimed) {
        _updateRewards(msg.sender);

        User storage user = users[msg.sender];

        claimed = user.rewards;

        if (claimed > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, claimed);

            emit Claim(msg.sender, claimed);
        }

        user.rewards = 0;
    }

    function _checkPoint(User storage _user) internal view returns (uint256) {
        return _user.rewards.add(accRewardPerShare.sub(_user.rewardPerSharePaid).mul(_user.totalUnderlying).div(PRECISION));
    }

    function pendingRewards(address _for) external view override returns (uint256) {
        User storage user = users[_for];

        return _checkPoint(user);
    }

    function distribute(uint256 _rewards) external override nonReentrant returns (uint256) {
        require(_rewards < type(uint256).max, "AbstractReward: Maximum limit exceeded");

        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

            accRewardPerShare = accRewardPerShare.add(_rewards.mul(PRECISION).div(totalSupply));

            emit Distribute(_rewards, accRewardPerShare);
        }

        return accRewardPerShare;
    }
}
