// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { AbstractVault } from "./AbstractVault.sol";
import { IWETH } from "../interfaces/IWETH.sol";

contract ETHVault is AbstractVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public wethAddress;

    event SetWrappedToken(address _wethAddress);

    function _addLiquidity(uint256 _amountIn) internal override returns (uint256) {
        require(_amountIn > 0, "ETHVault: Amount cannot be 0");
        require(underlyingToken == wethAddress, "ETHVault: Token not supported");

        if (msg.value > 0) {
            _wrapETH(_amountIn);
        } else {
            uint256 before = IERC20Upgradeable(underlyingToken).balanceOf(address(this));
            IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(underlyingToken).balanceOf(address(this)) - before;
        }

        return _amountIn;
    }

    function _wrapETH(uint256 _amountIn) internal {
        require(msg.value == _amountIn, "ETHVault: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }

    function setWrappedToken(address _wethAddress) external onlyOwner {
        require(wethAddress == address(0), "ETHVault: Cannot run this function twice");

        wethAddress = _wethAddress;

        emit SetWrappedToken(_wethAddress);
    }
}
