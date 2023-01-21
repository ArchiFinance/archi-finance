// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditManager {
    function vault() external view returns (address);

    function borrow(address _recipient, uint256 _borrowedAmount) external;

    function repay(address _recipient, uint256 _borrowedAmount) external;

    function claim(address _recipient) external returns (uint256 claimed);

    function balanceOf(address _recipient) external view returns (uint256);

    event Borrow(address _recipient, uint256 _borrowedAmount, uint256 _totalShares, uint256 _shares);
    event Repay(address _recipient, uint256 _borrowedAmount, uint256 _totalShares, uint256 _shares);
    event Harvest(uint256 _claimed, uint256 _accRewardPerShare);
    event Claim(address _recipient, uint256 _claimed);
}
