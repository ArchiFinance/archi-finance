// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IGmxVault {
    function totalTokenWeights() external view returns (uint256);

    function usdgAmounts(address _swapToken) external view returns (uint256);

    function tokenDecimals(address _swapToken) external view returns (uint256);

    function tokenWeights(address _swapToken) external view returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function maxUsdgAmounts(address _token) external view returns (uint256);

    function guaranteedUsd(address _token) external view returns (uint256);

    function stableTokens(address _token) external view returns (bool);

    function poolAmounts(address _token) external view returns (uint256);

    function reservedAmounts(address _token) external view returns (uint256);

    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function mintBurnFeeBasisPoints() external view returns (uint256);
}
