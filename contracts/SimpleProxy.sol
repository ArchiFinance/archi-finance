// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Multicall } from "./libraries/Multicall.sol";

contract SimpleProxy is Multicall {
    address public owner;
    address public pendingOwner;

    error NotAuthorized();
    error Failed(bytes _returnData);
    event Execute(address indexed _sender, address indexed _target, uint256 _value, bytes _data);

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotAuthorized();
        _;
    }

    /// @notice used to initialize the contract
    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice uset pending owner
    function setPendingOwner(address _owner) external onlyOwner {
        pendingOwner = _owner;
    }

    /// @notice accept pending owner
    function acceptOwner() external onlyOwner {
        owner = pendingOwner;

        pendingOwner = address(0);
    }

    /// @notice execute data
    function execute(address _target, bytes calldata _data) external payable onlyOwner returns (bytes memory) {
        (bool success, bytes memory returnData) = _target.call{ value: msg.value }(_data);

        if (!success) revert Failed(returnData);

        emit Execute(msg.sender, _target, msg.value, _data);

        return returnData;
    }
}
