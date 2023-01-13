// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGlpManager {
    function glp() external view returns (address);

    function usdg() external view returns (address);

    function vault() external view returns (address);

    function getAums() external view returns (uint256[] memory);

    function getAumInUsdg(bool maximise) external view returns (uint256);
}
