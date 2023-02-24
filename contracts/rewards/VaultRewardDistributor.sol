// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IBaseReward } from "./interfaces/IBaseReward.sol";
import { IVaultRewardDistributor } from "./interfaces/IVaultRewardDistributor.sol";

/* 
The VaultRewardDistributor is used to control the distribution ratio of the supplyRewardPool and borrowedRewardPool in the vault contract. 
When profits are sent to the VaultRewardDistributor's distribute function, 
the contract will also send them to the supplyRewardPool and borrowedRewardPool according to the preset ratio.
*/

contract VaultRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IVaultRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1000;
    uint256 private constant MAX_RATIO = 1000;
    uint256 private constant INITIAL_RATIO = 500;

    address public override stakingToken;
    address public override rewardToken;
    address public staker;
    address public distributor;
    address public supplyRewardPool;
    address public borrowedRewardPool;

    uint256 public supplyRewardPoolRatio;
    uint256 public borrowedRewardPoolRatio;

    modifier onlyStaker() {
        require(staker == msg.sender, "VaultRewardDistributor: Caller is not the staker");
        _;
    }

    modifier onlyDistributor() {
        require(distributor == msg.sender, "VaultRewardDistributor: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(
        address _staker,
        address _distributor,
        address _stakingToken,
        address _rewardToken
    ) external initializer {
        require(_staker != address(0), "VaultRewardDistributor: _staker cannot be 0x0");
        require(_distributor != address(0), "VaultRewardDistributor: _distributor cannot be 0x0");
        require(_stakingToken != address(0), "VaultRewardDistributor: _stakingToken cannot be 0x0");
        require(_rewardToken != address(0), "VaultRewardDistributor: _rewardToken cannot be 0x0");

        require(_staker.isContract(), "VaultRewardDistributor: _staker is not a contract");
        require(_stakingToken.isContract(), "VaultRewardDistributor: _stakingToken is not a contract");
        require(_rewardToken.isContract(), "VaultRewardDistributor: _rewardToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        staker = _staker;
        distributor = _distributor;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;

        supplyRewardPoolRatio = INITIAL_RATIO;
        borrowedRewardPoolRatio = INITIAL_RATIO;
    }

    /// @notice set suppliers reward pool ratio
    /// @param _ratio ratio
    function setSupplyRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio <= MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        supplyRewardPoolRatio = _ratio;
        borrowedRewardPoolRatio = MAX_RATIO - supplyRewardPoolRatio;

        emit SetSupplyRewardPoolRatio(_ratio);
    }

    /// @notice set borrowers reward pool ratio
    /// @param _ratio ratio
    function setBorrowedRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio <= MAX_RATIO, "VaultRewardDistributor: Maximum limit exceeded");

        borrowedRewardPoolRatio = _ratio;
        supplyRewardPoolRatio = MAX_RATIO - borrowedRewardPoolRatio;

        emit SetBorrowedRewardPoolRatio(_ratio);
    }

    /// @notice set SupplyRewardPool address
    /// @dev the address is supplyRewardPool in vault
    /// @param _rewardPool contract address
    function setSupplyRewardPool(address _rewardPool) public onlyOwner {
        require(_rewardPool != address(0), "VaultRewardDistributor: _rewardPool cannot be 0x0");
        require(supplyRewardPool == address(0), "VaultRewardDistributor: Cannot run this function twice");

        supplyRewardPool = _rewardPool;

        emit SetSupplyRewardPool(_rewardPool);
    }

    /// @notice set BorrowedRewardPool address
    /// @dev the address is BorrowedRewardPool in vault
    /// @param _rewardPool contract address
    function setBorrowedRewardPool(address _rewardPool) public onlyOwner {
        require(_rewardPool != address(0), "VaultRewardDistributor: _rewardPool cannot be 0x0");
        require(borrowedRewardPool == address(0), "VaultRewardDistributor: Cannot run this function twice");

        borrowedRewardPool = _rewardPool;

        emit SetBorrowedRewardPool(_rewardPool);
    }

    /// @notice deposit credit token
    /// @dev execute by staker only
    /// @param _amountIn token amount
    function stake(uint256 _amountIn) external override onlyStaker {
        require(_amountIn > 0, "VaultRewardDistributor: _amountIn cannot be 0");

        uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
        IERC20Upgradeable(stakingToken).safeTransferFrom(staker, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;

        emit Stake(_amountIn);
    }

    /// @notice withdraw credit token
    /// @dev execute by staker only
    /// @param _amountOut token amount
    function withdraw(uint256 _amountOut) external override onlyStaker returns (uint256) {
        require(_amountOut > 0, "VaultRewardDistributor: _amountOut cannot be 0");

        IERC20Upgradeable(stakingToken).safeTransfer(staker, _amountOut);

        emit Withdraw(_amountOut);

        return _amountOut;
    }

    /// @notice reward distribution
    /// @dev the distribution function will transfer from the caller to rewards
    /// @param _rewards reward amount
    function distribute(uint256 _rewards) external override nonReentrant onlyDistributor {
        require(_rewards > 0, "VaultRewardDistributor: _rewards cannot be 0");

        IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
        _rewards = IERC20Upgradeable(rewardToken).balanceOf(address(this));

        uint256 vaultRewards = (_rewards * supplyRewardPoolRatio) / PRECISION;
        uint256 borrowedRewards = (_rewards * borrowedRewardPoolRatio) / PRECISION;

        if (vaultRewards > 0) {
            _approve(rewardToken, supplyRewardPool, vaultRewards);
            IBaseReward(supplyRewardPool).distribute(vaultRewards);
        }

        if (borrowedRewards > 0) {
            _approve(rewardToken, borrowedRewardPool, borrowedRewards);

            IBaseReward(borrowedRewardPool).distribute(borrowedRewards);
        }

        /// @dev compatible event
        emit Distribute(_rewards, 0);
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("VaultRewardDistributor: Not allowed");
    }
}
