// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

contract MockGmxVaultPriceFeed {
    mapping(address => uint256) public prices;

    function setPrice(address _token, uint256 _price) external {
        prices[_token] = _price;
    }

    function getPrice(
        address _token,
        bool,
        bool,
        bool
    ) public view returns (uint256) {
        return prices[_token];
    }
}
