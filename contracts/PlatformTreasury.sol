// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract PlatformTreasury {
    using SafeERC20 for IERC20;
    using Address for address;

    address public operator;

    error NotAuthorized();
    error Failed(bytes _returnData);
    event WithdrawTo(address indexed _recipient, uint256 _amountOut);

    modifier onlyOperator() {
        require(msg.sender == operator, "PlatformTreasury: Caller is not the operator");
        _;
    }

    constructor(address _operator) {
        require(_operator != address(0), "PlatformTreasury: _operator cannot be 0x0");

        operator = _operator;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "PlatformTreasury: _operator cannot be 0x0");

        operator = _operator;
    }

    function withdrawTo(
        IERC20 _token,
        uint256 _amountOut,
        address _recipient
    ) external onlyOperator {
        require(address(_token) != address(0), "PlatformTreasury: _token cannot be 0x0");
        require(_amountOut > 0, "PlatformTreasury: _amountIn cannot be 0");

        _token.safeTransfer(_recipient, _amountOut);

        emit WithdrawTo(_recipient, _amountOut);
    }

    function execute(address _target, bytes calldata _data) external payable onlyOperator returns (bytes memory) {
        require(_target != address(0), "PlatformTreasury: _target cannot be 0x0");

        (bool success, bytes memory returnData) = _target.call{ value: msg.value }(_data);
    
        if (!success) revert Failed(returnData);

        return returnData;
    }
}
