// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./BaseReward.sol";

/* 
The CollateralReward inherits from BaseReward and disables the withdraw function. 
The withdrawFor function can only withdraw funds for the operator.
*/

contract CollateralReward is BaseReward {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice operator help user to withdraw
    /// @dev only execute by operator
    /// @param _amountOut amount withdrew
    function withdrawFor(address _recipient, uint256 _amountOut) public override nonReentrant onlyOperator returns (uint256) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        require(_amountOut <= user.totalUnderlying, "CollateralReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying - _amountOut;

        totalSupply = totalSupply - _amountOut;

        IERC20Upgradeable(stakingToken).safeTransfer(operator, _amountOut);

        emit Withdraw(_recipient, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }

    /// @notice user withdraw
    /// @dev forbid user to withdraw in CcollateralReward contract
    function withdraw(uint256) public override nonReentrant returns (uint256) {
        revert("CollateralReward: Not allowed");
    }
}
