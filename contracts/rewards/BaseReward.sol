// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./AbstractReward.sol";

contract BaseReward is AbstractReward {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(address _stakingToken, address _rewardToken) external initializer {
        __initial(_stakingToken, _rewardToken);
    }

    function stakeFor(address _recipient, uint256 _amountIn) public override nonReentrant {
        require(_amountIn > 0, "BaseReward: Amount cannot be 0");

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

    function withdraw(uint256 _amountOut) public override nonReentrant returns (uint256) {
        User storage user = users[msg.sender];

        require(_amountOut <= user.totalUnderlying, "BaseReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying.sub(_amountOut);

        totalSupply = totalSupply.sub(_amountOut);

        IERC20Upgradeable(stakingToken).safeTransfer(msg.sender, _amountOut);

        emit Withdraw(msg.sender, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }
}
