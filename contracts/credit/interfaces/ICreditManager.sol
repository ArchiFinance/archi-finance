// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditManager {
    function vault() external view returns (address);

    function borrow(address _recipient, uint256 _borrowedAmount) external;

    function repay(address _recipient, uint256 _borrowedAmount) external;

    event Borrow(address _recipient, uint256 _borrowedAmount, uint256 _totalShares, uint256 _shares);
    event Repay(address _recipient, uint256 _borrowedAmount, uint256 _totalShares, uint256 _shares);
    event Harvest(uint256 _claimed, uint256 _accRewardPerShare);
    event Claim(address _recipient, uint256 _claimed);
}
