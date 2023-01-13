// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CreditToken is ERC20 {
    address public operator;

    modifier onlyOperator() {
        require(msg.sender == operator, "CreditToken: Caller is not the operator");
        _;
    }

    constructor(address _operator, address _baseToken)
        ERC20(string(abi.encodePacked(ERC20(_baseToken).name(), " credit token")), string(abi.encodePacked("ct", ERC20(_baseToken).symbol())))
    {
        operator = _operator;
    }

    function mint(address _to, uint256 _amount) external onlyOperator {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyOperator {
        _burn(_from, _amount);
    }
}
