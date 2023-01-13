// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IAbstractReward } from "../rewards/interfaces/IAbstractReward.sol";
import { AbstractVault } from "./AbstractVault.sol";

contract ERC20Vault is AbstractVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function _addLiquidity(uint256 _amountIn) internal override returns (uint256) {
        require(_amountIn > 0, "ERC20Vault: Amount cannot be 0");

        uint256 before = IERC20Upgradeable(underlyingToken).balanceOf(address(this));
        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(underlyingToken).balanceOf(address(this)) - before;

        return _amountIn;
    }
}
