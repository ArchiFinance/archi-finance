// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Timelock {
    using SafeMath for uint256;

    event NewAdmin(address indexed _newAdmin);
    event NewPendingAdmin(address indexed _newPendingAdmin);
    event NewDelay(uint256 indexed _newDelay);
    event CancelTransaction(bytes32 indexed _txHash, address indexed _target, uint256 _value, string _signature, bytes _data, uint256 _eta);
    event ExecuteTransaction(bytes32 indexed _txHash, address indexed _target, uint256 _value, string _signature, bytes _data, uint256 _eta);
    event QueueTransaction(bytes32 indexed _txHash, address indexed _target, uint256 _value, string _signature, bytes _data, uint256 _eta);

    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MINIMUM_DELAY = 1 days;
    uint256 public constant MAXIMUM_DELAY = 30 days;

    address public admin;
    address public pendingAdmin;
    uint256 public delay;

    mapping(bytes32 => bool) public queuedTransactions;

    constructor(address _admin, uint256 _delay) {
        admin = _admin;

        _setDelay(_delay);
    }

    function _setDelay(uint256 _delay) internal {
        require(_delay >= MINIMUM_DELAY, "Timelock::_setDelay: Delay must exceed minimum delay.");
        require(_delay <= MAXIMUM_DELAY, "Timelock::_setDelay: Delay must not exceed maximum delay.");

        delay = _delay;

        emit NewDelay(delay);
    }

    function setDelay(uint256 _delay) public {
        require(msg.sender == address(this), "Timelock::setDelay: Call must come from Timelock.");

        _setDelay(_delay);
    }

    function acceptAdmin() public {
        require(msg.sender == pendingAdmin, "Timelock::acceptAdmin: Call must come from pendingAdmin.");
        admin = msg.sender;
        pendingAdmin = address(0);

        emit NewAdmin(admin);
    }

    function setPendingAdmin(address _pendingAdmin) public {
        require(msg.sender == address(this), "Timelock::setPendingAdmin: Call must come from Timelock.");
        pendingAdmin = _pendingAdmin;

        emit NewPendingAdmin(pendingAdmin);
    }

    function queueTransaction(
        address _target,
        uint256 _value,
        string memory _signature,
        bytes memory _data,
        uint256 _eta
    ) public returns (bytes32) {
        require(msg.sender == admin, "Timelock::queueTransaction: Call must come from admin.");
        require(_eta >= getBlockTimestamp().add(delay), "Timelock::queueTransaction: Estimated execution block must satisfy delay.");

        bytes32 txHash = keccak256(abi.encode(_target, _value, _signature, _data, _eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, _target, _value, _signature, _data, _eta);
        return txHash;
    }

    function cancelTransaction(
        address _target,
        uint256 _value,
        string memory _signature,
        bytes memory _data,
        uint256 _eta
    ) public {
        require(msg.sender == admin, "Timelock::cancelTransaction: Call must come from admin.");

        bytes32 txHash = keccak256(abi.encode(_target, _value, _signature, _data, _eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, _target, _value, _signature, _data, _eta);
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    function executeTransaction(
        address _target,
        uint256 _value,
        string memory _signature,
        bytes memory _data,
        uint256 _eta
    ) public payable returns (bytes memory) {
        require(msg.sender == admin, "Timelock::executeTransaction: Call must come from admin.");

        bytes32 txHash = keccak256(abi.encode(_target, _value, _signature, _data, _eta));
        require(queuedTransactions[txHash], "Timelock::executeTransaction: Transaction hasn't been queued.");
        require(getBlockTimestamp() >= _eta, "Timelock::executeTransaction: Transaction hasn't surpassed time lock.");
        require(getBlockTimestamp() <= _eta.add(GRACE_PERIOD), "Timelock::executeTransaction: Transaction is stale.");

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(_signature).length == 0) {
            callData = _data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(_signature))), _data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = _target.call{ value: _value }(callData);
        require(success, _getRevertMsg(returnData));

        emit ExecuteTransaction(txHash, _target, _value, _signature, _data, _eta);

        return returnData;
    }

    function getBlockTimestamp() internal view returns (uint256) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }
}
