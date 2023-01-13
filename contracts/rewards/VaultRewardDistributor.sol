// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IAbstractReward } from "./interfaces/IAbstractReward.sol";
import { IVaultRewardDistributor } from "./interfaces/IVaultRewardDistributor.sol";

contract VaultRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IVaultRewardDistributor {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1000;
    uint256 private constant MAX_RATIO = 1000;
    uint256 private constant INITAL_RATIO = 500;

    address public caller;
    address public stakingToken;
    address public rewardToken;
    address public supplyRewardPool;
    address public borrowedRewardPool;

    uint256 public supplyRewardPoolRatio;
    uint256 public borrowedRewardPoolRatio;

    modifier onlyCaller() {
        require(caller == msg.sender, "VaultRewardDistributor: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _caller,
        address _stakingToken,
        address _rewardToken,
        address _supplyRewardPool,
        address _borrowedRewardPool
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        caller = _caller;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        supplyRewardPool = _supplyRewardPool;
        borrowedRewardPool = _borrowedRewardPool;

        supplyRewardPoolRatio = INITAL_RATIO;
        borrowedRewardPoolRatio = INITAL_RATIO;
    }

    function setSupplyRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio.add(borrowedRewardPoolRatio) <= MAX_RATIO, "VaultRewardDistributor: Too large");

        supplyRewardPoolRatio = _ratio;

        emit SetSupplyRewardPoolRatio(_ratio);
    }

    function setBorrowedRewardPoolRatio(uint256 _ratio) public onlyOwner {
        require(_ratio.add(supplyRewardPoolRatio) <= MAX_RATIO, "VaultRewardDistributor: Too large");

        borrowedRewardPoolRatio = _ratio;

        emit SetBorrowedRewardPoolRatio(_ratio);
    }

    function stake(uint256 _amountIn) external override onlyCaller {
        require(_amountIn > 0, "VaultRewardDistributor: Amount cannot be 0");

        uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
        IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;

        emit Stake(_amountIn);
    }

    function withdraw(uint256 _amountOut) external override onlyCaller returns (uint256) {
        require(_amountOut > 0, "VaultRewardDistributor: Amount cannot be 0");

        IERC20Upgradeable(stakingToken).safeTransfer(msg.sender, _amountOut);

        emit Withdraw(_amountOut);

        return _amountOut;
    }

    function distribute(uint256 _rewards) external nonReentrant {
        require(_rewards < type(uint256).max, "VaultRewardDistributor: Maximum limit exceeded");

        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
            uint256 vaultRewards = _rewards.mul(supplyRewardPoolRatio).div(PRECISION);
            uint256 borrowedRewards = _rewards.mul(borrowedRewardPoolRatio).div(PRECISION);

            _approve(rewardToken, supplyRewardPool, vaultRewards);
            _approve(rewardToken, borrowedRewardPool, borrowedRewards);

            IAbstractReward(supplyRewardPool).distribute(vaultRewards);
            IAbstractReward(borrowedRewardPool).distribute(borrowedRewards);

            emit Distribute(_rewards);
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
