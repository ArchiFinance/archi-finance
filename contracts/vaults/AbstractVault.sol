// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IAbstractVault } from "./interfaces/IAbstractVault.sol";
import { Multicall } from "../libraries/Multicall.sol";
import { ShareLocker } from "./ShareLocker.sol";
import { IAbstractReward } from "../rewards/interfaces/IAbstractReward.sol";

abstract contract AbstractVault is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC20Upgradeable, Multicall, IAbstractVault {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public override underlyingToken;
    address public override supplyRewardPool;
    address public override borrowedRewardPool;

    address[] public creditManagers;

    mapping(address => address) public override creditManagersShareLocker;
    mapping(address => bool) public creditManagersCanBorrow;
    mapping(address => bool) public creditManagersCanRepay;

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

    function initialize(address _underlyingToken) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        __ERC20_init(
            string(abi.encodePacked(ERC20Upgradeable(_underlyingToken).name(), " vault shares")),
            string(abi.encodePacked("vs", ERC20Upgradeable(_underlyingToken).symbol()))
        );

        underlyingToken = _underlyingToken;
    }

    function addLiquidity(uint256 _amountIn) external payable returns (uint256) {
        _amountIn = _addLiquidity(_amountIn);

        _mint(address(this), _amountIn);
        _approve(address(this), supplyRewardPool, _amountIn);

        IAbstractReward(supplyRewardPool).stakeFor(msg.sender, _amountIn);

        emit AddLiquidity(msg.sender, _amountIn);

        return _amountIn;
    }

    /** @dev this function is defined in a child contract */
    function _addLiquidity(uint256 _amountIn) internal virtual returns (uint256);

    function removeLiquidity(uint256 _amountOut) external {
        _burn(msg.sender, _amountOut);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _amountOut);

        emit RemoveLiquidity(msg.sender, _amountOut);
    }

    function borrow(uint256 _borrowedAmount) external override onlyCreditManagersCanBorrow(msg.sender) returns (uint256) {
        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        _mint(shareLocker, _borrowedAmount);
        _approve(shareLocker, borrowedRewardPool, _borrowedAmount);

        ShareLocker(shareLocker).stake(_borrowedAmount);

        emit Borrow(msg.sender, _borrowedAmount);

        return _borrowedAmount;
    }

    function repay(uint256 _borrowedAmount) external override onlyCreditManagersCanRepay(msg.sender) {
        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);

        address shareLocker = creditManagersShareLocker[msg.sender];

        ShareLocker(shareLocker).withdraw(_borrowedAmount);

        _burn(shareLocker, _borrowedAmount);

        emit Repay(msg.sender, _borrowedAmount);
    }

    function setSupplyRewardPool(address _rewardPool) external onlyOwner {
        require(supplyRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        supplyRewardPool = _rewardPool;

        emit SetSupplyRewardPool(_rewardPool);
    }

    function setBorrowedRewardPool(address _rewardPool) external onlyOwner {
        require(borrowedRewardPool == address(0), "AbstractVault: Cannot run this function twice");

        borrowedRewardPool = _rewardPool;

        emit SetBorrowedRewardPool(_rewardPool);
    }

    function availableLiquidity() public view returns (uint256) {
        return IERC20Upgradeable(underlyingToken).balanceOf(address(this));
    }

    function getBlockNumber() internal view virtual returns (uint256) {
        return block.number;
    }

    function creditManagersCount() external view returns (uint256) {
        return creditManagers.length;
    }

    function addCreditManager(address _creditManager) external onlyOwner {
        require(!creditManagersCanRepay[_creditManager], "AbstractVault: Not allowed");

        creditManagersCanBorrow[_creditManager] = true;
        creditManagersCanRepay[_creditManager] = true;
        creditManagersShareLocker[_creditManager] = address(new ShareLocker(address(this), _creditManager, borrowedRewardPool));

        creditManagers.push(_creditManager);

        emit AddCreditManager(_creditManager, creditManagersShareLocker[_creditManager]);
    }
}
