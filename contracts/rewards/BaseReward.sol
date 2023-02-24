// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IBaseReward } from "./interfaces/IBaseReward.sol";

/* 
The BaseReward contract is Archi's profit pool contract. 
The addresses of the supplyRewardPool and BorrowedRewardPool in the liquidity vault pool are created by the current contract. 
BaseReward is different from traditional reward contracts in that profits are immediately distributed. 
Additionally, the contract operator can help users withdraw funds on their behalf.
*/

contract BaseReward is Initializable, ReentrancyGuardUpgradeable, IBaseReward {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    struct User {
        uint256 totalUnderlying;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    address public override stakingToken;
    address public override rewardToken;
    address public operator;
    address public distributor;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;
    uint256 public queuedRewards;

    mapping(address => User) public users;

    modifier onlyOperator() {
        require(operator == msg.sender, "BaseReward: Caller is not the operator");
        _;
    }

    modifier onlyDistributor() {
        require(distributor == msg.sender, "BaseReward: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(
        address _operator,
        address _distributor,
        address _stakingToken,
        address _rewardToken
    ) external initializer {
        require(_operator != address(0), "BaseReward: _operator cannot be 0x0");
        require(_distributor != address(0), "BaseReward: _distributor cannot be 0x0");
        require(_stakingToken != address(0), "BaseReward: _stakingToken cannot be 0x0");
        require(_rewardToken != address(0), "BaseReward: _rewardToken cannot be 0x0");

        require(_stakingToken.isContract(), "BaseReward: _stakingToken is not a contract");
        require(_rewardToken.isContract(), "BaseReward: _rewardToken is not a contract");

        __ReentrancyGuard_init();

        stakingToken = _stakingToken;
        distributor = _distributor;
        rewardToken = _rewardToken;
        operator = _operator;
    }

    /// @notice deposit token
    /// @dev parameter refers to stakeFor
    function _stakeFor(address _recipient, uint256 _amountIn) internal {
        require(_recipient != address(0), "BaseReward: _recipient cannot be 0x0");
        require(_amountIn > 0, "BaseReward: _amountIn cannot be 0");

        _updateRewards(_recipient);

        {
            uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
            IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;
        }

        User storage user = users[_recipient];
        user.totalUnderlying = user.totalUnderlying + _amountIn;

        totalSupply = totalSupply + _amountIn;

        emit StakeFor(_recipient, _amountIn, totalSupply, user.totalUnderlying);
    }

    /// @notice deposit token
    /// @param _recipient user
    /// @param _amountIn deposit amount
    function stakeFor(address _recipient, uint256 _amountIn) public virtual override nonReentrant {
        _stakeFor(_recipient, _amountIn);
    }

    /// @notice withdraw token
    /// @dev parameter refers to withdraw
    function _withdraw(address _recipient, uint256 _amountOut) internal returns (uint256) {
        require(_recipient != address(0), "BaseReward: _recipient cannot be 0x0");
        require(_amountOut > 0, "BaseReward: _amountOut cannot be 0");

        _updateRewards(_recipient);

        User storage user = users[_recipient];

        require(_amountOut <= user.totalUnderlying, "BaseReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying - _amountOut;

        totalSupply = totalSupply - _amountOut;

        IERC20Upgradeable(stakingToken).safeTransfer(_recipient, _amountOut);

        emit Withdraw(_recipient, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }

    /// @notice withdraw token
    /// @param _amountOut withdraw amount
    function withdraw(uint256 _amountOut) public virtual override nonReentrant returns (uint256) {
        return _withdraw(msg.sender, _amountOut);
    }

    /// @notice operator help user to withdraw
    /// @param _amountOut withdraw amount
    function withdrawFor(address _recipient, uint256 _amountOut) public virtual override nonReentrant onlyOperator returns (uint256) {
        return _withdraw(_recipient, _amountOut);
    }

    function _updateRewards(address _recipient) internal {
        User storage user = users[_recipient];

        uint256 rewards = _checkpoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    /// @notice withdraw user reward
    /// @param _recipient user
    function claim(address _recipient) external override nonReentrant returns (uint256 claimed) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        claimed = user.rewards;

        if (claimed > 0) {
            user.rewards = 0;
            IERC20Upgradeable(rewardToken).safeTransfer(_recipient, claimed);
            emit Claim(_recipient, claimed);
        }
    }

    function _checkpoint(User storage _user) internal view returns (uint256) {
        if (_user.totalUnderlying == 0) return 0;

        return _user.rewards + ((accRewardPerShare - _user.rewardPerSharePaid) * _user.totalUnderlying) / PRECISION;
    }

    /// @notice check user reward
    /// @param _recipient user
    function pendingRewards(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return _checkpoint(user);
    }

    /// @notice check user deposit amount
    /// @return deposit amount
    function balanceOf(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return user.totalUnderlying;
    }

    /// @notice reward distribution
    /// @dev the distribution will transfer from the caller to rewards
    /// @param _rewards reward amount
    function distribute(uint256 _rewards) external override nonReentrant onlyDistributor {
        require(_rewards > 0, "BaseReward: _rewards cannot be 0");

        IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

        if (totalSupply == 0) {
            queuedRewards = queuedRewards + _rewards;
        } else {
            _rewards = _rewards + queuedRewards;
            accRewardPerShare = accRewardPerShare + (_rewards * PRECISION) / totalSupply;
            queuedRewards = 0;

            emit Distribute(_rewards, accRewardPerShare);
        }
    }
}
