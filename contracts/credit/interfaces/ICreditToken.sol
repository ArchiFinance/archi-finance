// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICreditToken {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}
