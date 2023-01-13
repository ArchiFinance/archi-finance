// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAddressProvider {
    event AddressSet(bytes32 indexed _key, address indexed _value);

    function getWETHGateway() external view returns (address);

    function getGmxRewardRouter() external view returns (address);

    function getLiquidator() external view returns (address);

    function getPriceOracle() external view returns (address);
}
