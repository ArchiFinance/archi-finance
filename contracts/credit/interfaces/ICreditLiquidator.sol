// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICreditLiquidator {
    function getGlpPrice(bool _isBuying) external view returns (uint256);

    function getBuyGlpToAmount(address _swapToken, uint256 _swapAmountIn) external view returns (uint256, uint256);

    function getSellGlpToAmount(address _swapToken, uint256 _swapAmountIn) external view returns (uint256, uint256);

    function getBuyGlpFromAmount(address _swapToken, uint256 _swapAmountIn) external view returns (uint256, uint256);

    function getSellGlpFromAmount(address _swapToken, uint256 _swapAmountIn) external view returns (uint256, uint256);

    function adjustForDecimals(
        uint256 _amountIn,
        uint256 _divDecimals,
        uint256 _mulDecimals
    ) external pure returns (uint256);
}
