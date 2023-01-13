// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IAddressProvider } from "./interfaces/IAddressProvider.sol";

bytes32 constant WETH_GATEWAP = "WETH_GATEWAP";
bytes32 constant PRICE_ORACLE = "PRICE_ORACLE";
bytes32 constant LIQUIDATER = "LIQUIDATER";
bytes32 constant GMX_REWARD_ROUTER = "GMX_REWARD_ROUTER";

contract AddressProvider is Ownable, IAddressProvider {
    mapping(bytes32 => address) public addresses;

    constructor() {
        emit AddressSet("ADDRESS_PROVIDER", address(this));
    }

    function getWETHGateway() external view override returns (address) {
        return _getAddress(WETH_GATEWAP);
    }

    function setWETHGateway(address _v) external onlyOwner {
        _setAddress(WETH_GATEWAP, _v);
    }

    function getGmxRewardRouter() external view override returns (address) {
        return _getAddress(GMX_REWARD_ROUTER);
    }

    function setGmxRewardRouter(address _v) external onlyOwner {
        _setAddress(GMX_REWARD_ROUTER, _v);
    }

    function getLiquidator() external view override returns (address) {
        return _getAddress(LIQUIDATER);
    }

    function setLiquidater(address _v) external onlyOwner {
        _setAddress(LIQUIDATER, _v);
    }

    function getPriceOracle() external view override returns (address) {
        return _getAddress(PRICE_ORACLE);
    }

    function setPriceOracle(address _v) external onlyOwner {
        _setAddress(PRICE_ORACLE, _v);
    }

    /// @return Address of key, reverts if the key doesn't exist
    function _getAddress(bytes32 _key) internal view returns (address) {
        address result = addresses[_key];
        require(result != address(0), "AddressProvider: Address not found");
        return result;
    }

    /// @dev Sets address to map by its key
    /// @param _key Key in string format
    /// @param _value Address
    function _setAddress(bytes32 _key, address _value) internal {
        addresses[_key] = _value;
        emit AddressSet(_key, _value);
    }
}
