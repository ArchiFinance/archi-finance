// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { Multicall } from "../libraries/Multicall.sol";
import { IAbstractVault } from "./interfaces/IAbstractVault.sol";
import { IShareLocker, ShareLocker } from "./ShareLocker.sol";
import { IBaseReward } from "../rewards/interfaces/IBaseReward.sol";

/* 
The AbstractVault is a liquidity deposit contract that inherits from the ERC20 contract. 
When users deposit liquidity, it generates vsToken 1:1 and pledges it to the supplyRewardPool to obtain rewards. 
When a CredityManager borrows, it also generates vsToken and pledges it to the borrowedRewardPool to obtain rewards. 
The vsToken pledged in the supplyRewardPool belongs to the user, while the vsToken pledged in the borrowedRewardPool belongs to the ShareLocker contract. 
After repayment, ShareLocker will automatically withdraw and burn them.
*/

abstract contract AbstractVault is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    Multicall,
    IAbstractVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address public override underlyingToken;
    address public override supplyRewardPool;
    address public override borrowedRewardPool;

    address[] public creditManagers;

    mapping(address => address) public override creditManagersShareLocker;
    mapping(address => bool) public override creditManagersCanBorrow;
    mapping(address => bool) public override creditManagersCanRepay;

    modifier onlyCreditManagersCanBorrow(address _sender) {
        require(creditManagersCanBorrow[_sender], "AbstractVault: Caller is not the vault manager");

        _;
    }

    modifier onlyCreditManagersCanRepay(address _sender) {
        require(creditManagersCanRepay[_sender], "AbstractVault: Caller is not the vault manager");

        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _underlyingToken) external initializer {
        require(_underlyingToken != address(0), "AbstractVault: _underlyingToken cannot be 0x0");
        require(_underlyingToken.isContract(), "AbstractVault: _underlyingToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        __ERC20_init(
            string(abi.encodePacked(ERC20Upgradeable(_underlyingToken).name(), " vault shares")),
            string(abi.encodePacked("vs", ERC20Upgradeable(_underlyingToken).symbol()))
        );

        underlyingToken = _underlyingToken;
    }

    /// @notice add liquidity
    /// @param _amountIn amount of underling token
    /// @return amount of liquidity
    function addLiquidity(uint256 _amountIn) external payable whenNotPaused returns (uint256) {
        require(_amountIn > 0, "AbstractVault: _amountIn cannot be 0");

        _amountIn = _addLiquidity(_amountIn);

        _mint(address(this), _amountIn);
        _approve(address(this), supplyRewardPool, _amountIn);

        IBaseReward(supplyRewardPool).stakeFor(msg.sender, _amountIn);

        emit AddLiquidity(msg.sender, _amountIn, block.timestamp);

        return _amountIn;
    }

    /** @dev this function is defined in a child contract */
    function _addLiquidity(uint256 _amountIn) internal virtual returns (uint256);

    /// @notice remove liquidity
    /// @param _amountOut amount of liquidity
    function removeLiquidity(uint256 _amountOut) external {
        require(_amountOut > 0, "AbstractVault: _amountOut cannot be 0");

        uint256 vsTokenBal = balanceOf(msg.sender);

        if (_amountOut > vsTokenBal) {
            IBaseReward(supplyRewardPool).withdrawFor(msg.sender, _amountOut - vsTokenBal);
        }

        _burn(msg.sender, _amountOut);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _amountOut);

        emit RemoveLiquidity(msg.sender, _amountOut, block.timestamp);
    }

    /// @notice borrowed from vault
    /// @param _borrowedAmount amount been borrowed
    /// @return borrowed amount
    function borrow(uint256 _borrowedAmount) external override whenNotPaused onlyCreditManagersCanBorrow(msg.sender) returns (uint256) {
        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        _mint(shareLocker, _borrowedAmount);
        _approve(shareLocker, borrowedRewardPool, _borrowedAmount);

        IShareLocker(shareLocker).stake(_borrowedAmount);

        emit Borrow(msg.sender, _borrowedAmount);

        return _borrowedAmount;
    }

    /// @notice repay vault
    /// @param _borrowedAmount repaid amount
    function repay(uint256 _borrowedAmount) external override onlyCreditManagersCanRepay(msg.sender) {
        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        IShareLocker(shareLocker).withdraw(_borrowedAmount);

        _burn(shareLocker, _borrowedAmount);

        emit Repay(msg.sender, _borrowedAmount);
    }

    /// @notice set supply reward pool
    /// @param _rewardPool reward pool address
    function setSupplyRewardPool(address _rewardPool) external onlyOwner {
        require(_rewardPool != address(0), "AbstractVault: _rewardPool cannot be 0x0");
        require(supplyRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        supplyRewardPool = _rewardPool;

        emit SetSupplyRewardPool(_rewardPool);
    }

    /// @notice set borrow reward pool
    /// @param _rewardPool reward pool address
    function setBorrowedRewardPool(address _rewardPool) external onlyOwner {
        require(_rewardPool != address(0), "AbstractVault: _rewardPool cannot be 0x0");
        require(borrowedRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        borrowedRewardPool = _rewardPool;

        emit SetBorrowedRewardPool(_rewardPool);
    }

    /// @notice return number of managers
    /// @return amount
    function creditManagersCount() external view returns (uint256) {
        return creditManagers.length;
    }

    /// @notice add credit manager
    function addCreditManager(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        require(_creditManager.isContract(), "AbstractVault: _creditManager is not a contract");

        require(!creditManagersCanBorrow[_creditManager], "AbstractVault: Not allowed");
        require(!creditManagersCanRepay[_creditManager], "AbstractVault: Not allowed");
        require(creditManagersShareLocker[_creditManager] == address(0), "AbstractVault: Not allowed");

        address shareLocker = address(new ShareLocker(address(this), _creditManager, borrowedRewardPool));

        creditManagersCanBorrow[_creditManager] = true;
        creditManagersCanRepay[_creditManager] = true;
        creditManagersShareLocker[_creditManager] = shareLocker;

        creditManagers.push(_creditManager);

        emit AddCreditManager(_creditManager, shareLocker);
    }

    /// @notice forbid credit manager to borrow
    /// @param _creditManager credit manager address
    function forbidCreditManagerToBorrow(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        creditManagersCanBorrow[_creditManager] = false;

        emit ForbidCreditManagerToBorrow(_creditManager);
    }

    /// @notice forbid credit manager to repay
    /// @param _creditManager credit manager address
    function forbidCreditManagersCanRepay(address _creditManager) external onlyOwner {
        require(_creditManager != address(0), "AbstractVault: _creditManager cannot be 0x0");
        creditManagersCanRepay[_creditManager] = false;

        emit ForbidCreditManagersCanRepay(_creditManager);
    }

    /// @notice pause vault to add liquidity
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice unpause vault to add liquidity
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("AbstractVault: Not allowed");
    }
}
