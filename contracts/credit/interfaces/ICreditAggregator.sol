// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface ICreditAggregator {
    function getGlpPrice(bool _isBuying) external view returns (uint256);

    function getBuyGlpToAmount(address _fromToken, uint256 _tokenAmountIn) external view returns (uint256, uint256);

    function getSellGlpToAmount(address _toToken, uint256 _glpAmountIn) external view returns (uint256, uint256);

    function getBuyGlpFromAmount(address _toToken, uint256 _glpAmountIn) external view returns (uint256, uint256);

    function getSellGlpFromAmount(address _fromToken, uint256 _tokenAmountIn) external view returns (uint256, uint256);

    function getSellGlpFromAmounts(address[] calldata _tokens, uint256[] calldata _amounts) external view returns (uint256 totalAmountOut, uint256[] memory);

    function getTokenPrice(address _token) external view returns (uint256);

    function adjustForDecimals(
        uint256 _amountIn,
        uint256 _divDecimals,
        uint256 _mulDecimals
    ) external pure returns (uint256);
}
