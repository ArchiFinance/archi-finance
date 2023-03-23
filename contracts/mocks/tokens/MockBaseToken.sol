// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBaseToken is ERC20 {
    constructor(address _baseToken)
        ERC20(string(abi.encodePacked(ERC20(_baseToken).name(), " Mock Token")), string(abi.encodePacked("mock", ERC20(_baseToken).symbol())))
    {}

    function mint(address _to, uint256 _amountIn) external {
        _mint(_to, _amountIn);
    }

    function burn(address _from, uint256 _amountIn) external {
        _burn(_from, _amountIn);
    }
}
