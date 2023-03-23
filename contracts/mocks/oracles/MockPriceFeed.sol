// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "../../interfaces/IPriceFeed.sol";

/// @title Simulate Chainlink Oracle Contract
contract MockPriceFeed is IPriceFeed {
    uint256 private _latestTimestamp;
    uint256 private _latestRound;
    int256 private _latestAnswer;

    mapping(uint256 => int256) private _prices;
    mapping(uint256 => uint256) private _timestamps;

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function setPrice(
        uint256 _roundId,
        uint256 _timestamp,
        int256 _price
    ) external {
        _prices[_roundId] = _price;
        _timestamps[_roundId] = _timestamp;

        _latestRound = _roundId;
        _latestTimestamp = _timestamp;
        _latestAnswer = _price;
    }

    function latestAnswer() external view override returns (int256) {
        return _latestAnswer;
    }

    function latestTimestamp() external view override returns (uint256) {
        return _latestTimestamp;
    }

    function latestRound() external view override returns (uint256) {
        return _latestRound;
    }

    function getAnswer(uint256 _roundId) external view override returns (int256) {
        return _prices[_roundId];
    }

    function getTimestamp(uint256 _roundId) external view override returns (uint256) {
        return _timestamps[_roundId];
    }
}
