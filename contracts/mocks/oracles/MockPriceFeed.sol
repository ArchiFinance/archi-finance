// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "../../interfaces/IPriceFeed.sol";

/// @title Simulate Chainlink Oracle Contract
contract MockPriceFeed is IPriceFeed {
    uint256 private _latestTimestamp;
    uint80 private _latestRound;
    int256 private _latestAnswer;

    mapping(uint256 => int256) private _prices;
    mapping(uint256 => uint256) private _timestamps;

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function setPrice(
        uint80 _roundId,
        uint256 _timestamp,
        int256 _price
    ) external {
        _prices[_roundId] = _price;
        _timestamps[_roundId] = _timestamp;

        _latestRound = _roundId;
        _latestAnswer = _price;
        _latestTimestamp = _timestamp;
    }

    function description() external pure override returns (string memory) {
        return "MockPriceFeed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (roundId, _prices[_roundId], _timestamps[_roundId], _timestamps[_roundId], _latestRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_latestRound, _latestAnswer, _latestTimestamp, _latestTimestamp, _latestRound);
    }
}
