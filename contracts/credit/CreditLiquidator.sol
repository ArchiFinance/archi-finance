// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import { ICreditLiquidator } from "./interfaces/ICreditLiquidator.sol";
import { IPriceOracle } from "../oracles/interfaces/IPriceOracle.sol";
import { IAddressProvider } from "../interfaces/IAddressProvider.sol";
import { IGmxRewardRouter } from "../depositers/interfaces/IGmxRewardRouter.sol";
import { IGlpManager } from "../depositers/interfaces/IGlpManager.sol";
import { IGmxVault } from "../depositers/interfaces/IGmxVault.sol";

contract CreditLiquidator is Initializable, ICreditLiquidator {
    using SafeMathUpgradeable for uint256;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant GMX_DIVISION_LOSS_COMPENSATION = 10000; // 0.01 %
    uint256 private constant PRICE_PRECISION = 1e30;
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant MINT_BURN_FEE_BASIS_POINTS = 25;
    uint256 private constant TAX_BASIS_POINTS = 50;
    uint8 private constant GLP_DECIMALS = 18;
    uint8 private constant USDG_DECIMALS = 18;

    address public addressProvider;
    address public router;
    address public glpManager;
    address public vault;
    address public usdg;
    address public glp;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _addressProvider) external initializer {
        addressProvider = _addressProvider;
    }

    function update() public {
        router = IAddressProvider(addressProvider).getGmxRewardRouter();
        glpManager = IGmxRewardRouter(router).glpManager();
        glp = IGlpManager(glpManager).glp();
        vault = IGlpManager(glpManager).vault();
        usdg = IGlpManager(glpManager).usdg();
    }

    // 1e30
    function getGlpPrice(bool _isBuying) public view override returns (uint256) {
        // uint256[] memory aums = IGlpManager(glpManager).getAums();

        // if (aums.length > 0) {
        //     uint256 aum;

        //     if (_isBuying) {
        //         aum = aums[0];
        //     } else {
        //         aum = aums[1];
        //     }

        //     uint256 totalSupply = _totalSupply(glp);

        //     if (totalSupply > 0) {
        //         return aum.mul(10**GLP_DECIMALS) / totalSupply;
        //     }
        // }

        uint256 aumInUsdg = IGlpManager(glpManager).getAumInUsdg(_isBuying);
        uint256 glpSupply = _totalSupply(glp);

        if (glpSupply > 0) {
            return aumInUsdg.mul(10**GLP_DECIMALS) / glpSupply;
        }

        return 0;
    }

    function getBuyGlpToAmount(address _swapToken, uint256 _swapAmountIn) external view override returns (uint256, uint256) {
        if (_swapToken == ZERO) _swapToken = address(0);

        uint256 swapTokenDecimals = IGmxVault(vault).tokenDecimals(_swapToken);
        uint256 glpPrice = getGlpPrice(true);
        uint256 tokenPrice = getTokenPrice(_swapToken);
        uint256 glpAmount = _swapAmountIn.mul(tokenPrice).div(glpPrice);
        glpAmount = adjustForDecimals(glpAmount, swapTokenDecimals, USDG_DECIMALS);
        // glpAmount = IGmxVault(vault).adjustForDecimals(glpAmount, _swapToken, usdg);

        uint256 usdgAmount = _swapAmountIn.mul(tokenPrice).div(PRICE_PRECISION);
        usdgAmount = adjustForDecimals(usdgAmount, swapTokenDecimals, USDG_DECIMALS);
        // usdgAmount = IGmxVault(vault).adjustForDecimals(usdgAmount, _swapToken, usdg);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_swapToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (glpAmount, feeBasisPoints);
    }

    function getBuyGlpFromAmount(address _swapToken, uint256 _swapAmountIn) external view override returns (uint256, uint256) {
        if (_swapToken == ZERO) _swapToken = address(0);

        uint256 swapTokenDecimals = IGmxVault(vault).tokenDecimals(_swapToken);
        uint256 glpPrice = getGlpPrice(true);
        uint256 tokenPrice = getTokenPrice(_swapToken);
        uint256 fromAmount = _swapAmountIn.mul(glpPrice).div(tokenPrice);
        fromAmount = adjustForDecimals(fromAmount, GLP_DECIMALS, swapTokenDecimals);
        // fromAmount = IGmxVault(vault).adjustForDecimals(fromAmount, glp, _swapToken);

        uint256 usdgAmount = _swapAmountIn.mul(glpPrice).div(PRICE_PRECISION);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_swapToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        fromAmount = fromAmount.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);

        return (fromAmount, feeBasisPoints);
    }

    // 1e30
    function getSellGlpToAmount(address _swapToken, uint256 _swapAmountIn) external view override returns (uint256, uint256) {
        if (_swapToken == ZERO) _swapToken = address(0);

        uint256 swapTokenDecimals = IGmxVault(vault).tokenDecimals(_swapToken);
        uint256 glpPrice = getGlpPrice(false);
        uint256 tokenPrice = getTokenPrice(_swapToken);
        uint256 fromAmount = _swapAmountIn.mul(glpPrice).div(tokenPrice);
        fromAmount = adjustForDecimals(fromAmount, GLP_DECIMALS, swapTokenDecimals);
        // fromAmount = IGmxVault(vault).adjustForDecimals(fromAmount, glp, _swapToken);

        uint256 usdgAmount = _swapAmountIn.mul(glpPrice).div(PRICE_PRECISION);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_swapToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        fromAmount = fromAmount.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (fromAmount, feeBasisPoints);
    }

    // 1e30
    function getSellGlpFromAmount(address _swapToken, uint256 _swapAmountIn) external view override returns (uint256, uint256) {
        if (_swapToken == ZERO) _swapToken = address(0);

        uint256 swapTokenDecimals = IGmxVault(vault).tokenDecimals(_swapToken);
        uint256 glpPrice = getGlpPrice(false);
        uint256 tokenPrice = getTokenPrice(_swapToken);
        uint256 glpAmount = _swapAmountIn.mul(tokenPrice).div(glpPrice);
        glpAmount = adjustForDecimals(glpAmount, swapTokenDecimals, USDG_DECIMALS);
        // glpAmount = IGmxVault(vault).adjustForDecimals(glpAmount, _swapToken, usdg);

        uint256 usdgAmount = _swapAmountIn.mul(tokenPrice).div(PRICE_PRECISION);
        usdgAmount = adjustForDecimals(usdgAmount, swapTokenDecimals, USDG_DECIMALS);
        // usdgAmount = IGmxVault(vault).adjustForDecimals(usdgAmount, _swapToken, usdg);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_swapToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);
        glpAmount = glpAmount.add(glpAmount.div(GMX_DIVISION_LOSS_COMPENSATION));

        return (glpAmount, feeBasisPoints);
    }

    function adjustForDecimals(
        uint256 _amountIn,
        uint256 _divDecimals,
        uint256 _mulDecimals
    ) public pure override returns (uint256) {
        return _amountIn.mul(10**_mulDecimals).div(10**_divDecimals);
    }

    function _totalSupply(address _token) internal view returns (uint256) {
        return IERC20Upgradeable(_token).totalSupply();
    }

    function getTokenPrice(address _token) public view returns (uint256) {
        address priceOracle = IAddressProvider(addressProvider).getPriceOracle();

        // 1e30
        return IPriceOracle(priceOracle).getPrice(_token);
    }
}
