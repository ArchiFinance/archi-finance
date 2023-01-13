// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IAbstractReward.sol";

interface ICollateralReward is IAbstractReward {
    function withdrawFor(address _recipient, uint256 _amountOut) external returns (uint256);
}
