// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { AbstractVault } from "./AbstractVault.sol";
import { IWETH } from "../interfaces/IWETH.sol";

contract ETHVault is AbstractVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function _addLiquidity(uint256 _amountIn) internal override returns (uint256) {
        require(_amountIn > 0, "ETHVault: Amount cannot be 0");

        if (msg.value > 0) {
            require(msg.value == _amountIn, "ETHVault: ETH amount mismatch");

            IWETH(WETH).deposit{ value: _amountIn }();
        } else {
            uint256 before = IERC20Upgradeable(underlyingToken).balanceOf(address(this));
            IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(underlyingToken).balanceOf(address(this)) - before;
        }

        return _amountIn;
    }
}
