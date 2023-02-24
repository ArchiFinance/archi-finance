// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IAddressProvider {
    function getGmxRewardRouterV1() external view returns (address);

    function getGmxRewardRouter() external view returns (address);

    function getCreditAggregator() external view returns (address);

    event AddressSet(bytes32 indexed _key, address indexed _value);
}
