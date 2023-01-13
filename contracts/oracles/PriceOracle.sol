// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultPriceFeed {
    function getPriceV2(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) external view returns (uint256);
}

contract PriceOracle {
    uint256 private constant PRICE_PRECISION = 1e30;
    uint256 public constant ONE_USD = PRICE_PRECISION;

    address public vaultPriceFeed;

    constructor(address _vaultPriceFeed) {
        vaultPriceFeed = _vaultPriceFeed;
    }

    function getPrice(address _token) external view returns (uint256) {
        return IVaultPriceFeed(vaultPriceFeed).getPriceV2(_token, true, true);
    }
}
