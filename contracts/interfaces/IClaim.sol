// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IClaim {
    function claim(address _recipient) external returns (uint256 claimed);
}
