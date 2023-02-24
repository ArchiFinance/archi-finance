// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { ICreditManager } from "../credit/interfaces/ICreditManager.sol";
import { IDepositor } from "../depositors/interfaces/IDepositor.sol";

/* 
This contract is used to bind the rewardTracker variable of the Depositor contract and CreditManager contract. 
It can be used to call the harvest method, and only authorized governance personnel can call this contract.
*/

contract CreditRewardTracker is Initializable {
    using AddressUpgradeable for address;

    address public owner;
    address public pendingOwner;
    uint256 public lastInteractedAt;
    uint256 public duration;

    address[] public managers;
    address[] public depositors;

    mapping(address => bool) private governors;

    error NotAuthorized();
    event NewGovernor(address indexed _sender, address _governor);
    event RemoveGovernor(address indexed _sender, address _governor);
    event Executed(address _sender, address _target, uint256 _claimed, uint256 _timestamp);

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotAuthorized();
        _;
    }

    modifier onlyGovernors() {
        if (!isGovernor(msg.sender)) revert NotAuthorized();
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "CreditRewardTracker: _owner cannot be 0x0");

        owner = _owner;

        governors[_owner] = true;
        duration = 10 minutes;
    }

    /// @notice set pending owner
    /// @param _owner owner address
    function setPendingOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "CreditRewardTracker: _owner cannot be 0x0");
        pendingOwner = _owner;
    }

    /// @notice accept owner
    function acceptOwner() external onlyOwner {
        owner = pendingOwner;

        pendingOwner = address(0);
    }

    /// @notice add new governor
    /// @param _newGovernor governor address
    function addGovernor(address _newGovernor) public onlyOwner {
        require(_newGovernor != address(0), "CreditRewardTracker: _newGovernor cannot be 0x0");
        require(!isGovernor(_newGovernor), "CreditRewardTracker: _newGovernor is already governor");

        governors[_newGovernor] = true;

        emit NewGovernor(msg.sender, _newGovernor);
    }

    /// @notice add governors
    /// @param _newGovernors governors array
    function addGovernors(address[] calldata _newGovernors) external onlyOwner {
        for (uint256 i = 0; i < _newGovernors.length; i++) {
            addGovernor(_newGovernors[i]);
        }
    }

    /// @notice remove governor
    /// @param _governor governor address
    function removeGovernor(address _governor) external onlyOwner {
        require(_governor != address(0), "CreditRewardTracker: _governor cannot be 0x0");
        require(isGovernor(_governor), "CreditRewardTracker: _governor is not a governor");

        governors[_governor] = false;

        emit RemoveGovernor(msg.sender, _governor);
    }

    /// @notice judge if its governor
    /// @param _governor governor address
    /// @return bool value
    function isGovernor(address _governor) public view returns (bool) {
        return governors[_governor];
    }

    /// @notice add CreditManager
    /// @param _manager CreditManager address
    function addManager(address _manager) public onlyOwner {
        require(_manager != address(0), "CreditRewardTracker: _manager cannot be 0x0");

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

    /// @notice set minimum execute time difference
    /// @param _duration time stamp
    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    /// @notice execute harvest in managers depositors
    function execute() external onlyGovernors {
        require(block.timestamp - lastInteractedAt >= duration, "CreditRewardTracker: Incorrect duration");

        lastInteractedAt = block.timestamp;

        for (uint256 i = 0; i < depositors.length; i++) {
            uint256 claimed = IDepositor(depositors[i]).harvest();

            emit Executed(msg.sender, depositors[i], claimed, lastInteractedAt);
        }

        for (uint256 i = 0; i < managers.length; i++) {
            uint256 claimed = ICreditManager(managers[i]).harvest();

            emit Executed(msg.sender, managers[i], claimed, lastInteractedAt);
        }
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
