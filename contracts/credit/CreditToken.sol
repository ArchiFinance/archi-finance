// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ICreditToken } from "./interfaces/ICreditToken.sol";

/* 
When a user generates a loan, 
the amount of GLP collateral will generate ctTokens in a 1:1 ratio and will be deposit to CollateralReward. 
When the user repays the loan or is liquidated, 
the ctTokens will automatically be withdrawn.
*/

contract CreditToken is ERC20, ICreditToken {
    address public operator;

    modifier onlyOperator() {
        require(msg.sender == operator, "CreditToken: Caller is not the operator");
        _;
    }

    /// @notice used to initialize the contract
    constructor(address _operator, address _baseToken)
        ERC20(string(abi.encodePacked(ERC20(_baseToken).name(), " credit token")), string(abi.encodePacked("ct", ERC20(_baseToken).symbol())))
    {
        require(_operator != address(0), "CreditToken: _operator cannot be 0x0");

        operator = _operator;
    }

    /** @dev Creates `_amount` tokens and assigns them to `_to`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `_to` cannot be the zero address.
     */
    function mint(address _to, uint256 _amount) external override onlyOperator {
        _mint(_to, _amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `_from` cannot be the zero address.
     * - `_from` must have at least `amount` tokens.
     */
    function burn(address _from, uint256 _amount) external override onlyOperator {
        _burn(_from, _amount);
    }
}
