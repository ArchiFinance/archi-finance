// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IAbstractVault {
    function borrow(uint256 _borrowedAmount) external returns (uint256);

    function repay(uint256 _borrowedAmount) external;

    function supplyRewardPool() external view returns (address);

    function borrowedRewardPool() external view returns (address);

    function underlyingToken() external view returns (address);

    function creditManagersShareLocker(address _creditManager) external view returns (address);

    function creditManagersCanBorrow(address _creditManager) external view returns (bool);

    function creditManagersCanRepay(address _creditManager) external view returns (bool);

    event AddLiquidity(address indexed _recipient, uint256 _amountIn, uint256 _timestamp);
    event RemoveLiquidity(address indexed _recipient, uint256 _amountOut, uint256 _timestamp);
    event Borrow(address indexed _creditManager, uint256 _borrowedAmount);
    event Repay(address indexed _creditManager, uint256 _borrowedAmount);
    event SetSupplyRewardPool(address _rewardPool);
    event SetBorrowedRewardPool(address _rewardPool);
    event AddCreditManager(address _creditManager, address _shareLocker);
    event ToggleCreditManagerToBorrow(address _creditManager, bool _oldState);
    event ToggleCreditManagersCanRepay(address _creditManager, bool _oldState);
}
