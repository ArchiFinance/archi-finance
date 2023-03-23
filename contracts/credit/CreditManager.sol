// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { ICreditManager } from "./interfaces/ICreditManager.sol";
import { IAbstractVault } from "../vaults/interfaces/IAbstractVault.sol";
import { IShareLocker } from "../vaults/interfaces/IShareLocker.sol";
import { IBaseReward } from "../rewards/interfaces/IBaseReward.sol";

/* 
This contract is used to bind the AbstractVault contract and implement lending and repayment operations. 
it needs to be bound to AbstractVault. 
note that the contract can only be called by the CreditCaller contract.
*/

contract CreditManager is Initializable, ReentrancyGuardUpgradeable, ICreditManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    address public override vault;
    address public caller;
    address public rewardTracker;
    uint256 public totalShares;
    uint256 public accRewardPerShare;
    uint256 public queuedRewards;

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

    modifier onlyRewardTracker() {
        require(rewardTracker == msg.sender, "CreditManager: Caller is not the reward tracker");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(
        address _vault,
        address _caller,
        address _rewardTracker
    ) external initializer {
        require(_vault != address(0), "CreditManager: _vault cannot be 0x0");
        require(_caller != address(0), "CreditManager: _caller cannot be 0x0");
        require(_rewardTracker != address(0), "CreditManager: _rewardTracker cannot be 0x0");

        require(_vault.isContract(), "CreditManager: _vault is not a contract");
        require(_caller.isContract(), "CreditManager: _caller is not a contract");
        require(_rewardTracker.isContract(), "CreditManager: _rewardTracker is not a contract");

        __ReentrancyGuard_init();

        vault = _vault;
        caller = _caller;
        rewardTracker = _rewardTracker;
    }

    /// @notice leverage loans
    /// @param _recipient user
    /// @param _borrowedAmount borrow amount
    function borrow(address _recipient, uint256 _borrowedAmount) external override onlyCaller {
        _harvest();
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        address underlyingToken = IAbstractVault(vault).underlyingToken();
        uint256 shares = IAbstractVault(vault).borrow(_borrowedAmount);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        totalShares = totalShares + shares;
        user.shares = user.shares + shares;

        emit Borrow(_recipient, _borrowedAmount, totalShares, user.shares);
    }

    /// @notice repay loans
    /// @param _recipient user
    /// @param _borrowedAmount repaid amount
    /// @param _repayAmountDuringLiquidation the actual amount that can be repaid when the user undergoes liquidation
    /// @param _liquidating if liquidation occurs, true will be passed in, and _repayAmountDuringLiquidation may be 0 at the same time.
    function repay(
        address _recipient,
        uint256 _borrowedAmount,
        uint256 _repayAmountDuringLiquidation,
        bool _liquidating
    ) external override onlyCaller {
        _harvest();
        _updateRewards(_recipient);

        address underlyingToken = IAbstractVault(vault).underlyingToken();

        if (_liquidating) {
            if (_repayAmountDuringLiquidation > 0) {
                _approve(underlyingToken, vault, _repayAmountDuringLiquidation);
                IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _repayAmountDuringLiquidation);
            }
        } else {
            _approve(underlyingToken, vault, _borrowedAmount);
            IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);
        }

        User storage user = users[_recipient];
        totalShares = totalShares - _borrowedAmount;
        user.shares = user.shares - _borrowedAmount;

        IAbstractVault(vault).repay(_borrowedAmount, _repayAmountDuringLiquidation, _liquidating);

        emit Repay(_recipient, _borrowedAmount, _repayAmountDuringLiquidation, _liquidating, totalShares, user.shares);
    }

    function _harvest() internal returns (uint256) {
        address shareLocker = IAbstractVault(vault).creditManagersShareLocker(address(this));
        uint256 claimed = IShareLocker(shareLocker).harvest();

        if (claimed > 0) {
            if (totalShares == 0) {
                queuedRewards = queuedRewards + claimed;
            } else {
                claimed = claimed + queuedRewards;
                accRewardPerShare = accRewardPerShare + (claimed * PRECISION) / totalShares;
                queuedRewards = 0;

                emit Harvest(claimed, accRewardPerShare);
            }
        }

        return claimed;
    }

    /// @notice harvest interest
    /// @return amount of interest harvested
    function harvest() external override nonReentrant onlyRewardTracker returns (uint256) {
        return _harvest();
    }

    function _updateRewards(address _recipient) internal {
        User storage user = users[_recipient];

        uint256 rewards = _checkpoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    /// @notice get user interest
    /// @param _recipient user
    /// @return claimed user interest amount
    function claim(address _recipient) external override nonReentrant returns (uint256 claimed) {
        _harvest();
        _updateRewards(_recipient);

        address rewardPool = IAbstractVault(vault).borrowedRewardPool();
        address rewardToken = IBaseReward(rewardPool).rewardToken();

        User storage user = users[_recipient];

        claimed = user.rewards;

        if (claimed > 0) {
            user.rewards = 0;
            IERC20Upgradeable(rewardToken).safeTransfer(_recipient, claimed);

            emit Claim(_recipient, claimed);
        }
    }

    /// @notice update user interest
    /// @return amount of interest
    function _checkpoint(User storage _user) internal view returns (uint256) {
        if (_user.shares == 0) return 0;

        return _user.rewards + ((accRewardPerShare - _user.rewardPerSharePaid) * _user.shares) / PRECISION;
    }

    /// @notice check user interest
    /// @return amount of interest
    function pendingRewards(address _recipient) public view returns (uint256) {
        User storage user = users[_recipient];

        return _checkpoint(user);
    }

    /// @notice check user amount of shares
    /// @return shares
    function balanceOf(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return user.shares;
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
