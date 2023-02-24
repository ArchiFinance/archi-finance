// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { AbstractVault } from "./AbstractVault.sol";
import { IWETH } from "../interfaces/IWETH.sol";

/* 
Inherits from the AbstractVault contract.
Refer to the AbstractVault contract.
*/

contract ETHVault is AbstractVault {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public wethAddress;

    event SetWrappedToken(address _wethAddress);

    function _addLiquidity(uint256 _amountIn) internal override returns (uint256) {
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

    /// @notice set wrapped token address 
    /// @param _wethAddress weth address
    function setWrappedToken(address _wethAddress) external onlyOwner {
        require(_wethAddress != address(0), "ETHVault: _wethAddress cannot be 0x0");
        require(_wethAddress.isContract(), "ETHVault: _wethAddress is not a contract");
        require(wethAddress == address(0), "ETHVault: Cannot run this function twice");

        wethAddress = _wethAddress;

        emit SetWrappedToken(_wethAddress);
    }
}
