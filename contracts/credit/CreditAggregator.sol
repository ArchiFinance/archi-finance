// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { ICreditAggregator } from "./interfaces/ICreditAggregator.sol";
import { IAddressProvider } from "../interfaces/IAddressProvider.sol";
import { IGmxRewardRouter } from "../depositors/interfaces/IGmxRewardRouter.sol";
import { IGlpManager } from "../depositors/interfaces/IGlpManager.sol";
import { IGmxVault } from "../depositors/interfaces/IGmxVault.sol";

/* 
This contract is mainly used to obtain information about the GMX contract, 
such as calculating the GLP price, 
determining how many tokens users can receive by selling GLP, 
how many tokens are required to buy GLP, and the interface for calculating token prices in the GMX deposit pool.
*/

contract CreditAggregator is Initializable, ICreditAggregator {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant GMX_DIVISION_LOSS_COMPENSATION = 10000; // 0.01 %
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant MINT_BURN_FEE_BASIS_POINTS = 25;
    uint256 private constant TAX_BASIS_POINTS = 50;
    uint8 private constant GLP_DECIMALS = 18;
    uint8 private constant USDG_DECIMALS = 18;
    uint8 private constant PRICE_DECIMALS = 30;

    address public addressProvider;
    address public router;
    address public glpManager;
    address public vault;
    address public usdg;
    address public glp;

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _addressProvider) external initializer {
        require(_addressProvider != address(0), "CreditAggregator: _addressProvider cannot be 0x0");
        require(_addressProvider.isContract(), "CreditAggregator: _addressProvider is not a contract");

        addressProvider = _addressProvider;
    }

    /// @notice if GMX updates contract address, it can be automatically corrected
    function update() public {
        router = IAddressProvider(addressProvider).getGmxRewardRouter();
        glpManager = IGmxRewardRouter(router).glpManager();
        glp = IGlpManager(glpManager).glp();
        vault = IGlpManager(glpManager).vault();
        usdg = IGlpManager(glpManager).usdg();
    }

    /// @notice get GLP USD price
    /// @param _isBuying if true, return buy price, if false, return sell price
    /// @return price GLP usd price, precision 1e30
    function getGlpPrice(bool _isBuying) public view override returns (uint256 price) {
        /// @dev other way
        // uint256[] memory aums = IGlpManager(glpManager).getAums();

        // if (aums.length > 0) {
        //     uint256 aum;

        //     if (_isBuying) {
        //         aum = aums[0];
        //     } else {
        //         aum = aums[1];
        //     }

        //     uint256 glpSupply = _totalSupply(glp);

        //     if (glpSupply > 0) {
        //         return aum.mul(10**PRICE_DECIMALS) / glpSupply;
        //     }
        // }

        uint256 aumInUsdg = IGlpManager(glpManager).getAumInUsdg(_isBuying);
        uint256 glpSupply = _totalSupply(glp);

        if (glpSupply > 0) {
            price = aumInUsdg.mul(10**PRICE_DECIMALS).div(glpSupply);
        }
    }

    /* 
        glpPrice = 939690091372936156490347029512
        btcPrice = 23199207122640000000000000000000000
        ethPrice = 1652374189683000000000000000000000
        usdcPrice = 1000000000000000000000000000000

        # glp to token
        3422 × 1e18 × 0.939 × 1e30  / btcPrice / 1e18 glp decimals
        3422 × 1e18 × 0.939 × 1e30 / ethPrice / 1e18 glp decimals
        3422 × 1e18 × 0.939 × 1e30 / usdcPrice / 1e18 glp decimals

        # token to glp
        2 × 1e8 × btcPrice  / glpPrice / 1e8 token decimals
        2 × 1e18 × ethPrice / glpPrice / 1e18 token decimals
        300 × 1e6 × usdcPrice / glpPrice / 1e6 token decimals
     */

    /// @notice calculate the amount of GLP can be bought with token
    /// @param _fromToken token address
    /// @param _tokenAmountIn token amount
    /// @return GLP amount, amount precision correspond to token decimals
    /// @return gmx fee, precision 100
    function getBuyGlpToAmount(address _fromToken, uint256 _tokenAmountIn) external view override returns (uint256, uint256) {
        require(_fromToken != address(0), "CreditAggregator: _fromToken cannot be 0x0");
        require(_tokenAmountIn > 0, "CreditAggregator: _tokenAmountIn cannot be 0");

        uint256 tokenPrice = IGmxVault(vault).getMinPrice(_fromToken);
        uint256 glpPrice = getGlpPrice(true);
        uint256 glpAmount = _tokenAmountIn.mul(tokenPrice).div(glpPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_fromToken);
        uint256 usdgAmount = _tokenAmountIn.mul(tokenPrice).div(10**PRICE_DECIMALS);

        glpAmount = adjustForDecimals(glpAmount, tokenDecimals, GLP_DECIMALS);
        usdgAmount = adjustForDecimals(usdgAmount, tokenDecimals, USDG_DECIMALS);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_fromToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (glpAmount, feeBasisPoints);
    }

    /// @notice calculate amount of token GLP can be bought with sold token
    /// @param _fromToken token address
    /// @param _tokenAmountIn token amount
    /// @return GLP amount, amount precision correspond to token decimals
    /// @return gmx fee, precision 100
    function getSellGlpFromAmount(address _fromToken, uint256 _tokenAmountIn) external view override returns (uint256, uint256) {
        require(_fromToken != address(0), "CreditAggregator: _fromToken cannot be 0x0");
        require(_tokenAmountIn > 0, "CreditAggregator: _tokenAmountIn cannot be 0");

        uint256 tokenPrice = IGmxVault(vault).getMaxPrice(_fromToken);
        uint256 glpPrice = getGlpPrice(false);

        uint256 glpAmount = _tokenAmountIn.mul(tokenPrice).div(glpPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_fromToken);
        uint256 usdgAmount = _tokenAmountIn.mul(tokenPrice).div(10**PRICE_DECIMALS);

        glpAmount = adjustForDecimals(glpAmount, tokenDecimals, GLP_DECIMALS);
        usdgAmount = adjustForDecimals(usdgAmount, tokenDecimals, USDG_DECIMALS);

        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_fromToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        glpAmount = glpAmount.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);
        glpAmount = glpAmount.add(glpAmount.div(GMX_DIVISION_LOSS_COMPENSATION));

        return (glpAmount, feeBasisPoints);
    }

    /// @notice calculate amount of token can be bought with GLP
    /// @param _toToken token address
    /// @param _glpAmountIn token amount
    /// @return token amount, precision 1e18
    /// @return gmx fee, precision 100
    function getBuyGlpFromAmount(address _toToken, uint256 _glpAmountIn) external view override returns (uint256, uint256) {
        require(_toToken != address(0), "CreditAggregator: _toToken cannot be 0x0");
        require(_glpAmountIn > 0, "CreditAggregator: _glpAmountIn cannot be 0");

        uint256 tokenPrice = IGmxVault(vault).getMinPrice(_toToken);
        uint256 glpPrice = getGlpPrice(true);

        uint256 tokenAmountOut = _glpAmountIn.mul(glpPrice).div(tokenPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_toToken);

        tokenAmountOut = adjustForDecimals(tokenAmountOut, GLP_DECIMALS, tokenDecimals);

        uint256 usdgAmount = _glpAmountIn.mul(glpPrice).div(10**PRICE_DECIMALS);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_toToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, true);

        tokenAmountOut = tokenAmountOut.mul(BASIS_POINTS_DIVISOR).div(BASIS_POINTS_DIVISOR - feeBasisPoints);

        return (tokenAmountOut, feeBasisPoints);
    }

    /// @notice calculate amount of tokens glp can sell for
    /// @param _toToken token token address
    /// @param _glpAmountIn glp token amount
    /// @return token amount, precision 1e18
    /// @return gmx fee, precision 100
    function getSellGlpToAmount(address _toToken, uint256 _glpAmountIn) external view override returns (uint256, uint256) {
        require(_toToken != address(0), "CreditAggregator: _toToken cannot be 0x0");
        require(_glpAmountIn > 0, "CreditAggregator: _glpAmountIn cannot be 0");

        uint256 tokenPrice = IGmxVault(vault).getMaxPrice(_toToken);
        uint256 glpPrice = getGlpPrice(false);
        uint256 tokenAmountOut = _glpAmountIn.mul(glpPrice).div(tokenPrice);
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_toToken);

        tokenAmountOut = adjustForDecimals(tokenAmountOut, GLP_DECIMALS, tokenDecimals);

        uint256 usdgAmount = _glpAmountIn.mul(glpPrice).div(10**PRICE_DECIMALS);
        uint256 feeBasisPoints = IGmxVault(vault).getFeeBasisPoints(_toToken, usdgAmount, MINT_BURN_FEE_BASIS_POINTS, TAX_BASIS_POINTS, false);

        tokenAmountOut = tokenAmountOut.mul(BASIS_POINTS_DIVISOR - feeBasisPoints).div(BASIS_POINTS_DIVISOR);

        return (tokenAmountOut, feeBasisPoints);
    }

    /// @notice format presion
    /// @param _amountIn token amount
    /// @param _divDecimals current precision
    /// @param _mulDecimals target precision
    /// @return amountIn in target presion
    function adjustForDecimals(
        uint256 _amountIn,
        uint256 _divDecimals,
        uint256 _mulDecimals
    ) public pure override returns (uint256) {
        return _amountIn.mul(10**_mulDecimals).div(10**_divDecimals);
    }

    /// @notice get GMX vault info
    /// @param _token token address
    /// @return poolTotalUSD Current Pool Amount
    /// @return poolMaxPoolCapacity Max Pool Capacity
    /// @return poolAvailables available
    /// @return tokenPrice token price
    function getVaultPool(address _token)
        external
        view
        returns (
            uint256 poolTotalUSD,
            uint256 poolMaxPoolCapacity,
            uint256 poolAvailables,
            uint256 tokenPrice
        )
    {
        tokenPrice = getTokenPrice(_token);

        bool isStable = IGmxVault(vault).stableTokens(_token);
        uint256 availableAmount = IGmxVault(vault).poolAmounts(_token).sub(IGmxVault(vault).reservedAmounts(_token));
        uint256 tokenDecimals = IGmxVault(vault).tokenDecimals(_token);
        uint256 availableUsd = isStable
            ? IGmxVault(vault).poolAmounts(_token).mul(tokenPrice).div(10**tokenDecimals)
            : availableAmount.mul(tokenPrice).div(10**tokenDecimals);

        poolTotalUSD = availableUsd.add(IGmxVault(vault).guaranteedUsd(_token));
        poolMaxPoolCapacity = IGmxVault(vault).maxUsdgAmounts(_token);
        poolAvailables = poolTotalUSD.mul(10**tokenDecimals).div(tokenPrice);
    }

    /// @notice Get token total supply
    /// @param _token token address
    /// @return total supply
    function _totalSupply(address _token) internal view returns (uint256) {
        return IERC20Upgradeable(_token).totalSupply();
    }

    /// @notice get token price
    /// @param _token address
    /// @return calculate average price based on getMaxPrice & getMinPrice
    function getTokenPrice(address _token) public view override returns (uint256) {
        uint256 price0 = getMinPrice(_token);
        uint256 price1 = getMaxPrice(_token);

        return calcDiff(price0, price1);
    }

    /// @notice calc average price
    /// @param _price0 min price
    /// @param _price1 max price
    /// @return average price
    function calcDiff(uint256 _price0, uint256 _price1) public pure returns (uint256) {
        uint256 diff = 0;
        uint256 price = _price0;

        if (_price0 > _price1) {
            diff = _price0 - _price1;

            price = _price1;
        } else {
            diff = _price1 - _price0;
        }

        if (diff > 0) {
            diff = diff / 2;
        }

        return price + diff;
    }

    /// @notice get token max price
    /// @param _token token address
    /// @return get GMX vault getMaxPrice
    function getMaxPrice(address _token) public view returns (uint256) {
        return IGmxVault(vault).getMaxPrice(_token);
    }

    /// @notice get token min price
    /// @param _token token address
    /// @return get GMX vault getMinPrice
    function getMinPrice(address _token) public view returns (uint256) {
        return IGmxVault(vault).getMinPrice(_token);
    }
}
