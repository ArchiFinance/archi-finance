// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract PlatformTreasury {
    using SafeERC20 for IERC20;
    using Address for address;

    address public operator;

    event WithdrawTo(address indexed _user, uint256 _amount);

    modifier onlyOperator() {
        require(msg.sender == operator, "PlatformTreasury: Caller is not the operator");
        _;
    }

    constructor(address _operator) {
        operator = _operator;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function setOperator(address _op) external onlyOperator {
        operator = _op;
    }

    function withdrawTo(
        IERC20 _token,
        uint256 _amountOut,
        address _to
    ) external onlyOperator {
        _token.safeTransfer(_to, _amountOut);

        emit WithdrawTo(_to, _amountOut);
    }

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOperator returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{ value: _value }(_data);

        return (success, result);
    }
}
