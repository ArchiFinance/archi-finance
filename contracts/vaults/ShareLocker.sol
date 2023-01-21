// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAbstractReward } from "../rewards/interfaces/IAbstractReward.sol";

contract ShareLocker {
    using SafeERC20 for IERC20;

    address public vault;
    address public creditManager;
    address public rewardPool;

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
        vault = _vault;
        creditManager = _creditManager;
        rewardPool = _rewardPool;
    }

    function stake(uint256 _amountIn) public onlyVault {
        _claim();

        IAbstractReward(rewardPool).stakeFor(address(this), _amountIn);
    }

    function withdraw(uint256 _amountOut) public onlyVault {
        _claim();

        IAbstractReward(rewardPool).withdraw(_amountOut);
    }

    function _claim() internal returns (uint256 claimed) {
        address rewardToken = IAbstractReward(rewardPool).rewardToken();

        claimed = IAbstractReward(rewardPool).claim(address(this));

        if (claimed > 0) {
            IERC20(rewardToken).transfer(creditManager, claimed);
        }
    }

    function harvest() external onlyCreditManager returns (uint256) {
        return _claim();
    }

    function pendingRewards() public view returns (uint256) {
        return IAbstractReward(rewardPool).pendingRewards(address(this));
    }
}
