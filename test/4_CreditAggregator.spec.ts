/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { evmSnapshotRun, impersonatedSigner, removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as AddressProvider } from "../scripts/modules/AddressProvider";
import { main as CreditAggregator } from "../scripts/modules/CreditAggregator";
import { loadFixture } from "ethereum-waffle";
import { deployProxyAdmin } from "./LoadFixture";
import { CreditAggregator as CreditAggregatorInterface } from "../typechain/CreditAggregator";
import { AddressProvider as AddressProviderInterface } from "../typechain/AddressProvider";

describe("CreditAggregator contract", () => {
    let aggregator: CreditAggregatorInterface;
    let addressProvider: AddressProviderInterface;

    beforeEach(async () => {
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        addressProvider = await AddressProvider();

        aggregator = await CreditAggregator(proxyAdmin.address, addressProvider.address);

        await addressProvider.setGmxRewardRouter(`0xB95DB5B167D75e6d04227CfFFA61069348d271F5`);
        await aggregator.update();
    });

    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const Liquidator = await ethers.getContractFactory("CreditAggregator", deployer);
        const liquidator = await Liquidator.deploy();
        const instance = await liquidator.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditAggregator: _addressProvider cannot be 0x0");
        expect(
            TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin.address, instance.interface.encodeFunctionData("initialize", [deployer.address]))
        ).to.be.revertedWith("CreditAggregator: _addressProvider is not a contract");
    });

    it("Test #getGlpPrice", async () => {
        const glpBuyPrice = await aggregator.getGlpPrice(true);
        expect(glpBuyPrice).to.be.above(BigNumber.from("0")); // > 0 USD < 2 USD
        expect(glpBuyPrice).to.be.below(BigNumber.from(ethers.utils.parseUnits("2", 30)));

        const glpSellPrice = await aggregator.getGlpPrice(false);
        expect(glpSellPrice).to.be.above(BigNumber.from("0")); // > 0 USD < 2 USD
        expect(glpSellPrice).to.be.below(BigNumber.from(ethers.utils.parseUnits("2", 30)));

        const [deployer] = await ethers.getSigners();

        const glpAddress = `0x4277f8f2c384827b5273592ff7cebd9f2c1ac258`;
        const minter = await impersonatedSigner("0x3963FfC9dff443c2A94f21b129D429891E32ec18"); // glp manager
        const glp = await ethers.getContractAt(require("../scripts/abis/Glp"), glpAddress, deployer);

        await evmSnapshotRun(async () => {
            const glpTotalSupply = await glp.totalSupply();
            await glp.connect(minter).burn(`0x4e971a87900b931ff39d1aad67697f49835400b6`, glpTotalSupply);
            await aggregator.getGlpPrice(true);
        });
    });

    it("Test #getBuyGlpToAmount", async () => {
        expect(aggregator.getBuyGlpToAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _fromToken cannot be 0x0");
        expect(aggregator.getBuyGlpToAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _tokenAmountIn cannot be 0");

        const result = await aggregator.getBuyGlpToAmount(TOKENS.WETH, ethers.utils.parseEther("5"));
        const glpAmount = result[0];
        const feeBasisPoints = result[1];

        expect(glpAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getSellGlpFromAmount", async () => {
        expect(aggregator.getSellGlpFromAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _fromToken cannot be 0x0");
        expect(aggregator.getSellGlpFromAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _tokenAmountIn cannot be 0");

        const result = await aggregator.getSellGlpFromAmount(TOKENS.WETH, ethers.utils.parseEther("2"));
        const glpAmount = result[0];
        const feeBasisPoints = result[1];

        expect(glpAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getSellGlpFromAmounts", async () => {
        expect(aggregator.getSellGlpFromAmounts([TOKENS.WETH, TOKENS.USDT], [ethers.utils.parseEther("2")])).to.be.revertedWith(
            "CreditAggregator: Length mismatch"
        );

        const result = await aggregator.getSellGlpFromAmounts([TOKENS.WETH], [ethers.utils.parseEther("2")]);

        expect(result[0]).to.be.above(BigNumber.from("0"));
        expect(result[1][0]).to.be.above(BigNumber.from("0"));
    });

    it("Test #setPriceFeeds #setAdjustmentBasisPoints #validateTokenPrice", async () => {
        const wethPrice = await aggregator.getMaxPrice(TOKENS.WETH);
        const fraxPrice = await aggregator.getMaxPrice(TOKENS.FRAX);

        await aggregator.setPriceFeeds(TOKENS.WETH, `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612`);
        await aggregator.setPriceFeeds(TOKENS.USDT, `0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7`);
        await aggregator.setPriceFeeds(TOKENS.USDC, `0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3`);
        await aggregator.setPriceFeeds(TOKENS.WBTC, `0x6ce185860a4963106506C203335A2910413708e9`);
        await aggregator.setPriceFeeds(TOKENS.DAI, `0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB`);
        await aggregator.setPriceFeeds(TOKENS.LINK, `0x86E53CF1B870786351Da77A57575e79CB55812CB`);
        await aggregator.setPriceFeeds(TOKENS.UNI, `0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720`);

        expect(aggregator.setAdjustmentBasisPoints(TOKENS.WETH, 200)).to.be.revertedWith("CreditAggregator: MAX_ADJUSTMENT_BASIS_POINTS limit exceeded");

        await aggregator.setAdjustmentBasisPoints(TOKENS.WETH, 100);
        await aggregator.setAdjustmentBasisPoints(TOKENS.USDT, 100);

        await aggregator.getMinPrice(TOKENS.WETH);

        try {
            await aggregator.validateTokenPrice(TOKENS.WETH, 0);
        } catch (error: any) {
            expect(error.message).to.match(/CreditAggregator: _price cannot be 0/);
        }

        try {
            await aggregator.validateTokenPrice(TOKENS.WETH, wethPrice.mul(2));
        } catch (error: any) {
            expect(error.message).to.match(/CreditAggregator: Price overflowed/);
        }

        try {
            await aggregator.validateTokenPrice(TOKENS.WETH, wethPrice.div(2));
        } catch (error: any) {
            expect(error.message).to.match(/CreditAggregator: Price overflowed/);
        }

        const [deployer] = await ethers.getSigners();

        const MockPriceFeedFactory = await ethers.getContractFactory("MockPriceFeed", deployer);
        const MockPriceFeed = await MockPriceFeedFactory.deploy();
        const mockPriceFeed = await MockPriceFeed.deployed();

        await aggregator.setPriceFeeds(TOKENS.FRAX, mockPriceFeed.address);
        await mockPriceFeed.setPrice(1, 0, fraxPrice);

        try {
            await aggregator.validateTokenPrice(TOKENS.FRAX, fraxPrice);
        } catch (error: any) {
            expect(error.message).to.match(/CreditAggregator: The oracle may be down or paused/);
        }

        const testTimeAt = Math.floor(new Date().getTime() / 1000);
        await mockPriceFeed.setPrice(2, testTimeAt, 0);

        try {
            await aggregator.validateTokenPrice(TOKENS.FRAX, fraxPrice);
        } catch (error: any) {
            expect(error.message).to.match(/CreditAggregator: Invalid price/);
        }
    });

    it("Test #getBuyGlpFromAmount", async () => {
        expect(aggregator.getBuyGlpFromAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _toToken cannot be 0x0");
        expect(aggregator.getBuyGlpFromAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _glpAmountIn cannot be 0");

        const result = await aggregator.getBuyGlpFromAmount(TOKENS.WETH, ethers.utils.parseEther("3000"));
        const fromAmount = result[0];
        const feeBasisPoints = result[1];
        expect(fromAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getSellGlpToAmount", async () => {
        expect(aggregator.getSellGlpToAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _toToken cannot be 0x0");
        expect(aggregator.getSellGlpToAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _glpAmountIn cannot be 0");

        const result = await aggregator.getSellGlpToAmount(TOKENS.WETH, ethers.utils.parseEther("2"));
        const fromAmount = result[0];
        const feeBasisPoints = result[1];

        expect(fromAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getVaultPool", async () => {
        await aggregator.getVaultPool(TOKENS.WETH);
    });

    it("Test #calcDiff", async () => {
        await aggregator.calcDiff(BigNumber.from("100"), BigNumber.from("200"));
        await aggregator.calcDiff(BigNumber.from("200"), BigNumber.from("100"));
    });

    it("Test #renounceOwnership", async () => {
        expect(aggregator.renounceOwnership()).to.be.revertedWith("CreditAggregator: Not allowed");
    });
});
