// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _setupDecimals
    ) ERC20(_name, _symbol) {
        _decimals = _setupDecimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address _to, uint256 _amountIn) external {
        _mint(_to, _amountIn);
    }

    function burn(address _from, uint256 _amountIn) external {
        _burn(_from, _amountIn);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function mockApprove(
        address owner,
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        _approve(owner, spender, amount);
        return true;
    }
}
