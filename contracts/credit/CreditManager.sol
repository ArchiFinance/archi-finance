// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { ICreditManager } from "./interfaces/ICreditManager.sol";
import { IAbstractVault } from "../vaults/interfaces/IAbstractVault.sol";
import { IShareLocker } from "../vaults/interfaces/IShareLocker.sol";
import { IAbstractReward } from "../rewards/interfaces/IAbstractReward.sol";

contract CreditManager is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ICreditManager {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1e18;

    address public override vault;
    address public caller;
    uint256 public totalShares;
    uint256 public accRewardPerShare;

    struct User {
        uint256 shares;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    mapping(address => User) public users;

    modifier onlyCaller() {
        require(caller == msg.sender, "CreditManager: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _vault, address _caller) external initializer {
        __ReentrancyGuard_init();

        vault = _vault;
        caller = _caller;
    }

    function borrow(address _recipient, uint256 _borrowedAmount) external override onlyCaller {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        address underlyingToken = IAbstractVault(vault).underlyingToken();
        uint256 shares = IAbstractVault(vault).borrow(_borrowedAmount);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        totalShares = totalShares.add(shares);
        user.shares = user.shares.add(shares);

        emit Borrow(_recipient, _borrowedAmount, totalShares, user.shares);
    }

    function repay(address _recipient, uint256 _borrowedAmount) external override onlyCaller {
        _updateRewards(_recipient);

        address underlyingToken = IAbstractVault(vault).underlyingToken();

        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);

        _approve(underlyingToken, vault, _borrowedAmount);

        User storage user = users[_recipient];
        totalShares = totalShares.sub(_borrowedAmount);
        user.shares = user.shares.sub(_borrowedAmount);

        IAbstractVault(vault).repay(_borrowedAmount);

        emit Repay(_recipient, _borrowedAmount, totalShares, user.shares);
    }

    function harvest() public {
        address shareLocker = IAbstractVault(vault).creditManagersShareLocker(address(this));
        uint256 claimed = IShareLocker(shareLocker).claim();

        accRewardPerShare = accRewardPerShare.add(claimed.mul(PRECISION).div(totalShares));

        emit Harvest(claimed, accRewardPerShare);
    }

    function _updateRewards(address _for) internal {
        User storage user = users[_for];

        uint256 rewards = _checkPoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    function claim() public nonReentrant returns (uint256 claimed) {
        _updateRewards(msg.sender);

        address rewardPool = IAbstractVault(vault).borrowedRewardPool();
        address rewardToken = IAbstractReward(rewardPool).rewardToken();

        User storage user = users[msg.sender];
        claimed = user.rewards;

        if (claimed > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, claimed);

            emit Claim(msg.sender, claimed);
        }

        user.rewards = 0;
    }

    function _checkPoint(User storage _user) internal view returns (uint256) {
        return _user.rewards.add(accRewardPerShare.sub(_user.rewardPerSharePaid).mul(_user.shares).div(PRECISION));
    }

    function pendingRewards(address _for) public view returns (uint256) {
        User storage user = users[_for];

        return _checkPoint(user);
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
