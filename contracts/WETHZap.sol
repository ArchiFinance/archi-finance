// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IWETH } from "./interfaces/IWETH.sol";
import { IWETHZap } from "./interfaces/IWETHZap.sol";

contract WETHZap is IWETHZap {
    using SafeERC20 for IERC20;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public wethAddress;

    constructor(address _weth) {
        wethAddress = _weth;
    }

    function zap(address _fromToken, uint256 _amountIn) external payable override returns (uint256) {
        if (_isETH(_fromToken)) {
            require(msg.value == _amountIn, "WETHZap: ETH amount mismatch");

            IWETH(wethAddress).deposit{ value: _amountIn }();
            IERC20(wethAddress).safeTransfer(msg.sender, _amountIn);
        } else {
            require(_fromToken == wethAddress, "WETHZap: fromToken unsupported");

            IERC20(wethAddress).safeTransferFrom(msg.sender, address(this), _amountIn);
            IWETH(wethAddress).withdraw(_amountIn);

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{ value: _amountIn }("");
            require(success, "WETHZap: ETH transfer failed");
        }

        return _amountIn;
    }

    function _isETH(address _token) internal pure returns (bool) {
        return _token == ZERO || _token == address(0);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
