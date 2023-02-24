// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IAllowlist } from "./interfaces/IAllowlist.sol";

/* 
The Allowlist contract is primarily used to set up a list of whitelisted users. 
The CreditCaller contract will bind to this contract address, 
and when a user applies for a loan, it will check whether the user is on the whitelist.
*/

contract Allowlist is Ownable, IAllowlist {
    bool public passed;

    mapping(address => bool) public accounts;

    event Permit(address[] indexed _account, uint256 _timestamp);
    event Forbid(address[] indexed _account, uint256 _timestamp);
    event TogglePassed(bool _currentState, uint256 _timestamp);

    /// @notice used to initialize the contract
    constructor(bool _passed) {
        passed = _passed;
    }

    // @notice permit account
    /// @param _accounts user array
    function permit(address[] calldata _accounts) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i] != address(0), "Allowlist: Account cannot be 0x0");

            accounts[_accounts[i]] = true;
        }

        emit Permit(_accounts, block.timestamp);
    }

    /// @notice forbid account
    /// @param _accounts user array
    function forbid(address[] calldata _accounts) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            accounts[_accounts[i]] = false;
        }

        emit Forbid(_accounts, block.timestamp);
    }

    /// @notice toggle allow list
    function togglePassed() public onlyOwner {
        passed = !passed;

        emit TogglePassed(passed, block.timestamp);
    }

    /// @notice check account
    /// @param _account user address
    /// @return boolean
    function can(address _account) external view override returns (bool) {
        if (passed) return true;

        return accounts[_account];
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("Allowlist: Not allowed");
    }
}
