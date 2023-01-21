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
    address public operator;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;

    mapping(address => User) public users;

    modifier onlyOperator() {
        require(operator == msg.sender, "AbstractReward: Caller is not the operator");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _operator,
        address _stakingToken,
        address _rewardToken
    ) external initializer {
        __ReentrancyGuard_init();

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        operator = _operator;
    }

    function _stakeFor(address _recipient, uint256 _amountIn) internal {
        _updateRewards(_recipient);

        require(_amountIn > 0, "AbstractReward: Amount cannot be 0");

        {
            uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
            IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;
        }

        User storage user = users[_recipient];
        user.totalUnderlying = user.totalUnderlying.add(_amountIn);

        totalSupply = totalSupply.add(_amountIn);

        emit StakeFor(_recipient, _amountIn, totalSupply, user.totalUnderlying);
    }

    function stakeFor(address _recipient, uint256 _amountIn) public virtual override nonReentrant {
        _stakeFor(_recipient, _amountIn);
    }

    function _withdraw(address _recipient, uint256 _amountOut) internal returns (uint256) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        require(_amountOut <= user.totalUnderlying, "AbstractReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying.sub(_amountOut);

        totalSupply = totalSupply.sub(_amountOut);

        IERC20Upgradeable(stakingToken).safeTransfer(_recipient, _amountOut);

        emit Withdraw(_recipient, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }

    function withdraw(uint256 _amountOut) public virtual override nonReentrant returns (uint256) {
        return _withdraw(msg.sender, _amountOut);
    }

    function withdrawFor(address _recipient, uint256 _amountOut) public virtual override nonReentrant onlyOperator returns (uint256) {
        return _withdraw(_recipient, _amountOut);
    }

    function _updateRewards(address _recipient) internal {
        User storage user = users[_recipient];

        uint256 rewards = _checkpoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    function claim(address _recipient) external override nonReentrant returns (uint256 claimed) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        claimed = user.rewards;

        if (claimed > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(_recipient, claimed);
            emit Claim(_recipient, claimed);
        }

        user.rewards = 0;
    }

    function _checkpoint(User storage _user) internal view returns (uint256) {
        return _user.rewards.add(accRewardPerShare.sub(_user.rewardPerSharePaid).mul(_user.totalUnderlying).div(PRECISION));
    }

    function pendingRewards(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return _checkpoint(user);
    }

    function balanceOf(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return user.totalUnderlying;
    }

    function distribute(uint256 _rewards) external override nonReentrant {
        require(_rewards < type(uint256).max, "AbstractReward: Maximum limit exceeded");

        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

            accRewardPerShare = accRewardPerShare.add(_rewards.mul(PRECISION).div(totalSupply));

            emit Distribute(_rewards, accRewardPerShare);
        }
    }
}
