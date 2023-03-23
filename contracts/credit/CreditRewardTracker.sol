// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IRewardTracker } from "../interfaces/IRewardTracker.sol";
import { ICreditManager } from "../credit/interfaces/ICreditManager.sol";
import { IDepositor } from "../depositors/interfaces/IDepositor.sol";

/* 
This contract is used to bind the rewardTracker variable of the Depositor contract and CreditManager contract. 
It can be used to call the harvest method, and only authorized governance personnel can call this contract.
*/

contract CreditRewardTracker is Initializable, IRewardTracker {
    using AddressUpgradeable for address;

    uint256 private constant MAX_DEPOSITOR_SIZE = 8;
    uint256 private constant MAX_MANAGER_SIZE = 12;

    address public owner;
    address public pendingOwner;

    uint256[2] public lastInteractedAt;

    address[] public managers;
    address[] public depositors;

    mapping(address => bool) private vaultCanExecute;

    error NotAuthorized();
    event Executed(address _sender, address _target, uint256 _claimed, uint256 _timestamp);
    event ToggleVaultCanExecute(address _vault, bool _state);

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotAuthorized();
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "CreditRewardTracker: _owner cannot be 0x0");

        owner = _owner;
    }

    /// @notice set pending owner
    /// @param _owner owner address
    function setPendingOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "CreditRewardTracker: _owner cannot be 0x0");

        pendingOwner = _owner;
    }

    /// @notice accept owner
    function acceptOwner() external onlyOwner {
        require(pendingOwner != address(0), "CreditRewardTracker: pendingOwner cannot be 0x0");

        owner = pendingOwner;

        pendingOwner = address(0);
    }

    function toggleVaultCanExecute(address _vault) external onlyOwner {
        require(_vault != address(0), "CreditRewardTracker: _vault cannot be 0x0");

        vaultCanExecute[_vault] = !vaultCanExecute[_vault];

        emit ToggleVaultCanExecute(_vault, vaultCanExecute[_vault]);
    }

    /// @notice add CreditManager
    /// @param _manager CreditManager address
    function addManager(address _manager) public onlyOwner {
        require(_manager != address(0), "CreditRewardTracker: _manager cannot be 0x0");
        require(managers.length < MAX_MANAGER_SIZE, "CreditRewardTracker: Maximum limit exceeded");

        for (uint256 i = 0; i < managers.length; i++) {
            require(managers[i] != _manager, "CreditRewardTracker: Duplicate _manager");
        }

        managers.push(_manager);
    }

    /// @notice remove CreditManager
    /// @param _index CreditManager index
    function removeManager(uint256 _index) public onlyOwner {
        require(_index < managers.length, "CreditRewardTracker: Index out of range");

        managers[_index] = managers[managers.length - 1];
        managers.pop();
    }

    /// @notice add archi depositor
    /// @param _depositor depositor address
    function addDepositor(address _depositor) public onlyOwner {
        require(_depositor != address(0), "CreditRewardTracker: _depositor cannot be 0x0");
        require(depositors.length < MAX_DEPOSITOR_SIZE, "CreditRewardTracker: Maximum limit exceeded");

        for (uint256 i = 0; i < depositors.length; i++) {
            require(depositors[i] != _depositor, "CreditRewardTracker: Duplicate _depositor");
        }

        depositors.push(_depositor);
    }

    /// @notice remove archi depositor
    /// @param _index depositor index
    function removeDepositor(uint256 _index) public onlyOwner {
        require(_index < depositors.length, "CreditRewardTracker: Index out of range");

        depositors[_index] = depositors[depositors.length - 1];
        depositors.pop();
    }

    /// @dev helper function of HarvestDepositors
    function _harvestDepositors() internal {
        lastInteractedAt[0] = block.timestamp;

        for (uint256 i = 0; i < depositors.length; i++) {
            uint256 claimed = IDepositor(depositors[i]).harvest();

            emit Executed(msg.sender, depositors[i], claimed, lastInteractedAt[0]);
        }
    }

    /// @dev helper function of harvestManagers
    function _harvestManagers() internal {
        lastInteractedAt[1] = block.timestamp;

        for (uint256 i = 0; i < managers.length; i++) {
            uint256 claimed = ICreditManager(managers[i]).harvest();

            emit Executed(msg.sender, managers[i], claimed, lastInteractedAt[1]);
        }
    }

    /// @notice execute harvest in depositors
    function harvestDepositors() external onlyOwner {
        _harvestDepositors();
    }

    /// @notice execute harvest in managers
    function harvestManagers() external onlyOwner {
        _harvestManagers();
    }

    /// @notice execute harvest in managers depositors
    function execute() external override {
        if (vaultCanExecute[msg.sender]) {
            _harvestDepositors();
            return;
        }

        revert("CreditRewardTracker: Not allowed");
    }

    /// @notice managers length
    function managersLength() public view returns (uint256) {
        return managers.length;
    }

    /// @notice depositors length
    function depositorsLength() public view returns (uint256) {
        return depositors.length;
    }
}
