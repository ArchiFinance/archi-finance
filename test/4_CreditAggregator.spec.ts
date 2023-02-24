/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
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

        await addressProvider.setGmxRewardRouter(`0xB95DB5B167D75e6d04227CfFFA61069348d271F5`)
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
        await aggregator.update();

        const glpBuyPrice = await aggregator.getGlpPrice(true);
        expect(glpBuyPrice).to.be.above(BigNumber.from("0")); // > 0 USD < 2 USD
        expect(glpBuyPrice).to.be.below(BigNumber.from(ethers.utils.parseUnits("2", 30)));

        const glpSellPrice = await aggregator.getGlpPrice(false);
        expect(glpSellPrice).to.be.above(BigNumber.from("0")); // > 0 USD < 2 USD
        expect(glpSellPrice).to.be.below(BigNumber.from(ethers.utils.parseUnits("2", 30)));
    });

    it("Test #getBuyGlpToAmount", async () => {
        await aggregator.update();

        expect(aggregator.getBuyGlpToAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _fromToken cannot be 0x0");
        expect(aggregator.getBuyGlpToAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _tokenAmountIn cannot be 0");

        const result = await aggregator.getBuyGlpToAmount(TOKENS.WETH, ethers.utils.parseEther("5"));
        const glpAmount = result[0];
        const feeBasisPoints = result[1];

        expect(glpAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getSellGlpFromAmount", async () => {
        await aggregator.update();

        expect(aggregator.getSellGlpFromAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _fromToken cannot be 0x0");
        expect(aggregator.getSellGlpFromAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _tokenAmountIn cannot be 0");

        const result = await aggregator.getSellGlpFromAmount(TOKENS.WETH, ethers.utils.parseEther("2"));
        const glpAmount = result[0];
        const feeBasisPoints = result[1];

        expect(glpAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getBuyGlpFromAmount", async () => {
        await aggregator.update();

        expect(aggregator.getBuyGlpFromAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _toToken cannot be 0x0");
        expect(aggregator.getBuyGlpFromAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _glpAmountIn cannot be 0");

        const result = await aggregator.getBuyGlpFromAmount(TOKENS.WETH, ethers.utils.parseEther("3000"));
        const fromAmount = result[0];
        const feeBasisPoints = result[1];
        expect(fromAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getSellGlpToAmount", async () => {
        await aggregator.update();

        expect(aggregator.getSellGlpToAmount(ethers.constants.AddressZero, 0)).to.be.revertedWith("CreditAggregator: _toToken cannot be 0x0");
        expect(aggregator.getSellGlpToAmount(TOKENS.WETH, 0)).to.be.revertedWith("CreditAggregator: _glpAmountIn cannot be 0");

        const result = await aggregator.getSellGlpToAmount(TOKENS.WETH, ethers.utils.parseEther("2"));
        const fromAmount = result[0];
        const feeBasisPoints = result[1];

        expect(fromAmount).to.be.above(BigNumber.from("0"));
        expect(feeBasisPoints).to.be.above(BigNumber.from("0"));
    });

    it("Test #getVaultPool", async () => {
        await aggregator.update();
        await aggregator.getVaultPool(TOKENS.WETH);
    });

    it("Test #calcDiff", async () => {
        await aggregator.update();
        await aggregator.calcDiff(BigNumber.from("100"), BigNumber.from("200"));
        await aggregator.calcDiff(BigNumber.from("200"), BigNumber.from("100"));
    });
});
