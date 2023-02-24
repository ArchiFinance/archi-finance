// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IShareLocker } from "./interfaces/IShareLocker.sol";
import { IBaseReward } from "../rewards/interfaces/IBaseReward.sol";

/* 
Refer to the AbstractVault contract.
*/

contract ShareLocker is IShareLocker {
    using SafeERC20 for IERC20;
    using Address for address;

    address public override rewardPool;
    address public vault;
    address public creditManager;

    modifier onlyCreditManager() {
        require(creditManager == msg.sender, "ShareLocker: Caller is not the credit manager");
        _;
    }

    modifier onlyVault() {
        require(vault == msg.sender, "ShareLocker: Caller is not the vault");
        _;
    }

    constructor(
        address _vault,
        address _creditManager,
        address _rewardPool
    ) {
        require(_vault != address(0), "ShareLocker: _vault cannot be 0x0");
        require(_creditManager != address(0), "ShareLocker: _creditManager cannot be 0x0");
        require(_rewardPool != address(0), "ShareLocker: _rewardPool cannot be 0x0");

        require(_vault.isContract(), "ShareLocker: _vault is not a contract");
        require(_creditManager.isContract(), "ShareLocker: _creditManager is not a contract");
        require(_rewardPool.isContract(), "ShareLocker: _rewardPool is not a contract");

        vault = _vault;
        creditManager = _creditManager;
        rewardPool = _rewardPool;
    }

    /// @notice deposit vstoken
    /// @param _amountIn vsToken amount
    function stake(uint256 _amountIn) public override onlyVault {
        _claim();

        IBaseReward(rewardPool).stakeFor(address(this), _amountIn);
    }

    /// @notice withdraw vsToken
    /// @param _amountOut withdraw amount
    function withdraw(uint256 _amountOut) public override onlyVault {
        _claim();

        IBaseReward(rewardPool).withdraw(_amountOut);
    }

    /// @dev parameter refers to harvest
    function _claim() internal returns (uint256 claimed) {
        address rewardToken = IBaseReward(rewardPool).rewardToken();

        claimed = IBaseReward(rewardPool).claim(address(this));

        if (claimed > 0) {
            IERC20(rewardToken).transfer(creditManager, claimed);
        }
    }

    /// @notice withdraw locker reward
    function harvest() external override onlyCreditManager returns (uint256) {
        return _claim();
    }

    /// @notice check locker reward
    function pendingRewards() public view returns (uint256) {
        return IBaseReward(rewardPool).pendingRewards(address(this));
    }
}
