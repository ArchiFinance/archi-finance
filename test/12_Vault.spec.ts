/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as ETHVault } from "../scripts/modules/ETHVault";
import { main as ERC20Vault } from "../scripts/modules/ERC20Vault";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { main as SimpleProxy } from "../scripts/modules/SimpleProxy";
import { loadFixture } from "ethereum-waffle";
import { ERC20Vault as ERC20VaultInterface, ETHVault as ETHVaultInterface, MockToken, WETH9 } from "../typechain";
import { deployMockTokens, deployProxyAdmin } from "./LoadFixture";

describe("Vaults contract", () => {
    let usdt: MockToken;
    let weth: WETH9;
    let ethVault: ETHVaultInterface;
    let errorVault: ETHVaultInterface;
    let usdtVault: ERC20VaultInterface;

    after(async () => {
        removeDb();
    });

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const mockTokens = await loadFixture(deployMockTokens);

        ethVault = await ETHVault(proxyAdmin.address, TOKENS.WETH, "WETH");
        errorVault = await ETHVault(proxyAdmin.address, mockTokens.usdt.address, "ERROR_WETH");
        usdtVault = await ERC20Vault(proxyAdmin.address, mockTokens.usdt.address, "USDT");

        usdt = mockTokens.usdt;
        weth = mockTokens.weth;

        await ethVault.setWrappedToken(TOKENS.WETH);
        await errorVault.setWrappedToken(TOKENS.WETH);

        const ethSupply = await BaseReward(proxyAdmin.address, ethVault.address, deployer.address, ethVault.address, TOKENS.WETH, "ETHSupply");
        const usdtSupply = await BaseReward(proxyAdmin.address, usdtVault.address, deployer.address, usdtVault.address, TOKENS.WETH, "USDTSupply");
        const ethBorrowed = await BaseReward(proxyAdmin.address, ethVault.address, deployer.address, ethVault.address, TOKENS.WETH, "ETHBorrowed");
        const usdtBorrowed = await BaseReward(proxyAdmin.address, usdtVault.address, deployer.address, usdtVault.address, TOKENS.WETH, "USDTBorrowed");

        await ethVault.setSupplyRewardPool(ethSupply.address);

        expect(ethVault.setSupplyRewardPool(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _rewardPool cannot be 0x0");
        expect(ethVault.setSupplyRewardPool(ethBorrowed.address)).to.be.revertedWith("AbstractVault: Cannot run this function twice");

        await ethVault.setBorrowedRewardPool(ethBorrowed.address);

        expect(ethVault.setBorrowedRewardPool(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _rewardPool cannot be 0x0");
        expect(ethVault.setBorrowedRewardPool(ethBorrowed.address)).to.be.revertedWith("AbstractVault: Cannot run this function twice");

        await usdtVault.setSupplyRewardPool(usdtSupply.address);

        expect(usdtVault.setSupplyRewardPool(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _rewardPool cannot be 0x0");
        expect(usdtVault.setSupplyRewardPool(ethBorrowed.address)).to.be.revertedWith("AbstractVault: Cannot run this function twice");

        await usdtVault.setBorrowedRewardPool(usdtBorrowed.address);

        expect(usdtVault.setBorrowedRewardPool(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _rewardPool cannot be 0x0");
        expect(usdtVault.setBorrowedRewardPool(ethBorrowed.address)).to.be.revertedWith("AbstractVault: Cannot run this function twice");

        await weth.approve(ethVault.address, ethers.constants.MaxUint256);
        await usdt.approve(usdtVault.address, ethers.constants.MaxUint256);
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const Vault = await ethers.getContractFactory("ETHVault", deployer);
        const vault = await Vault.deploy();
        const instance = await vault.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("AbstractVault: _underlyingToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin.address, instance.interface.encodeFunctionData("initialize", [deployer.address]))
        ).to.be.revertedWith("AbstractVault: _underlyingToken is not a contract");
    });

    it("Test WETH vault #addLiquidity #removeLiquidity", async () => {
        const [deployer] = await ethers.getSigners();

        const ethAmountIn = ethers.utils.parseEther("1");
        const wethAmountIn = ethers.utils.parseEther("1");

        await weth.deposit({ value: wethAmountIn });
        // eth add liquidity
        expect(ethVault.addLiquidity(0)).to.be.revertedWith("AbstractVault: _amountIn cannot be 0");
        expect(ethVault.addLiquidity(ethAmountIn.mul(2), { value: ethAmountIn })).to.be.revertedWith("ETHVault: ETH amount mismatch");

        await ethVault.addLiquidity(wethAmountIn);
        await ethVault.addLiquidity(ethAmountIn, { value: ethAmountIn });

        const ethVaultSupplyRewardPool = await ethers.getContractAt("BaseReward", await ethVault.supplyRewardPool(), deployer);

        expect(await ethVaultSupplyRewardPool.balanceOf(deployer.address)).to.be.eql(BigNumber.from(ethAmountIn).add(wethAmountIn)); // check vsWETH balance
        expect(await weth.balanceOf(ethVault.address)).to.be.eql(BigNumber.from(ethAmountIn).add(wethAmountIn)); // check vault weth balance

        // remove liquidity
        expect(ethVault.removeLiquidity(0)).to.be.revertedWith("AbstractVault: _amountOut cannot be 0");
        await ethVault.removeLiquidity(wethAmountIn);

        expect(await ethVault.balanceOf(deployer.address)).to.be.equal(BigNumber.from("0"));
        expect(await weth.balanceOf(ethVault.address)).to.be.equal(BigNumber.from(wethAmountIn));
        expect(await ethVaultSupplyRewardPool.balanceOf(deployer.address)).to.be.eql(BigNumber.from(wethAmountIn)); // check vsWETH balance
    });

    it("Test USDT vault #addLiquidity #removeLiquidity", async () => {
        const [deployer] = await ethers.getSigners();

        const usdtAmountIn = ethers.utils.parseUnits("100", 6);

        // usdt add liquidity
        await usdt.mint(deployer.address, usdtAmountIn);
        await usdt.approve(usdtVault.address, usdtAmountIn);

        expect(usdtVault.addLiquidity(0)).to.be.revertedWith("AbstractVault: _amountIn cannot be 0");

        await usdtVault.addLiquidity(usdtAmountIn);

        const usdtVaultSupplyRewardPool = await ethers.getContractAt("BaseReward", await usdtVault.supplyRewardPool(), deployer);

        expect(await usdtVaultSupplyRewardPool.balanceOf(deployer.address)).to.be.equal(BigNumber.from(usdtAmountIn)); // check vsUSDT balance
        expect(await usdt.balanceOf(usdtVault.address)).to.be.equal(usdtAmountIn); // check vault usdt balance

        // remove liquidity
        expect(usdtVault.removeLiquidity(0)).to.be.revertedWith("AbstractVault: _amountOut cannot be 0");
        await usdtVault.removeLiquidity(usdtAmountIn);

        expect(await usdtVault.balanceOf(deployer.address)).to.be.equal(BigNumber.from("0"));
        expect(await usdt.balanceOf(usdtVault.address)).to.be.equal(BigNumber.from("0"));
    });

    it("Test #addCreditManager", async () => {
        const [deployer] = await ethers.getSigners();
        const simpleProxy1 = await SimpleProxy(deployer.address);

        expect(usdtVault.addCreditManager(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _creditManager cannot be 0x0");
        expect(usdtVault.addCreditManager(deployer.address)).to.be.revertedWith("AbstractVault: _creditManager is not a contract");

        await usdtVault.addCreditManager(simpleProxy1.address);
        await usdtVault.forbidCreditManagerToBorrow(simpleProxy1.address);
        expect(usdtVault.addCreditManager(simpleProxy1.address)).to.be.revertedWith("AbstractVault: Not allowed");

        const simpleProxy2 = await SimpleProxy(deployer.address);
        await usdtVault.addCreditManager(simpleProxy2.address);
        await usdtVault.forbidCreditManagersCanRepay(simpleProxy2.address);
        expect(usdtVault.addCreditManager(simpleProxy2.address)).to.be.revertedWith("AbstractVault: Not allowed");
        await usdtVault.forbidCreditManagerToBorrow(simpleProxy2.address);
        expect(usdtVault.addCreditManager(simpleProxy2.address)).to.be.revertedWith("AbstractVault: Not allowed");
    });

    it("Test #borrow #repay", async () => {
        const [deployer] = await ethers.getSigners();

        const simpleProxy = await SimpleProxy(deployer.address);

        const usdtAmountIn = ethers.utils.parseUnits("100", 6);
        const usdtBorrowedAmountIn = ethers.utils.parseUnits("50", 6);

        // approve
        await simpleProxy.execute(usdt.address, usdt.interface.encodeFunctionData("approve", [usdtVault.address, ethers.constants.MaxUint256]));

        // usdt add liquidity
        await usdt.mint(deployer.address, usdtAmountIn);
        await usdtVault.addLiquidity(usdtAmountIn);

        // borrow
        await usdtVault.addCreditManager(simpleProxy.address);
        await simpleProxy.execute(usdtVault.address, usdtVault.interface.encodeFunctionData("borrow", [usdtBorrowedAmountIn]));

        expect(await usdt.balanceOf(usdtVault.address)).to.be.eql(BigNumber.from(usdtBorrowedAmountIn));

        // repay
        await simpleProxy.execute(usdtVault.address, usdtVault.interface.encodeFunctionData("repay", [usdtBorrowedAmountIn]));
        expect(await usdt.balanceOf(usdtVault.address)).to.be.eql(BigNumber.from(usdtAmountIn));
    });

    it("Test #creditManagersCount", async () => {
        const [deployer] = await ethers.getSigners();

        await usdtVault.creditManagersCount();
    });

    it("Test #forbidCreditManagerToBorrow/#forbidCreditManagersCanRepay", async () => {
        const [deployer] = await ethers.getSigners();

        expect(usdtVault.forbidCreditManagerToBorrow(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _creditManager cannot be 0x0");
        expect(usdtVault.forbidCreditManagersCanRepay(ethers.constants.AddressZero)).to.be.revertedWith("AbstractVault: _creditManager cannot be 0x0");

        await usdtVault.forbidCreditManagerToBorrow(deployer.address);
        await usdtVault.forbidCreditManagersCanRepay(deployer.address);
    });

    it("Test #pause/#unpause", async () => {
        await usdtVault.pause();
        await usdtVault.unpause();
    });

    it("Test #setWrappedToken", async () => {
        const [deployer] = await ethers.getSigners();
        expect(ethVault.setWrappedToken(ethers.constants.AddressZero)).to.be.revertedWith("ETHVault: _wethAddress cannot be 0x0");
        expect(ethVault.setWrappedToken(deployer.address)).to.be.revertedWith("ETHVault: _wethAddress is not a contract");
        expect(ethVault.setWrappedToken(TOKENS.WETH)).to.be.revertedWith("ETHVault: Cannot run this function twice");
    });

    it("Test error vault", async () => {
        const ethAmountIn = ethers.utils.parseEther("1");

        expect(errorVault.addLiquidity(ethAmountIn, { value: ethAmountIn })).to.be.revertedWith("ETHVault: Token not supported");
    });

    it("Test #renounceOwnership", async () => {
        expect(ethVault.renounceOwnership()).to.be.revertedWith("AbstractVault: Not allowed");
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const borrowAmount = ethers.utils.parseUnits("100", 6);
        await weth.deposit({ value: borrowAmount });
        await weth.approve(ethVault.address, borrowAmount);

        // const newVault = await ethVault.connect(wrongSigner);
        expect(ethVault.borrow(borrowAmount)).to.be.revertedWith("AbstractVault: Caller is not the vault manager");
        expect(ethVault.repay(borrowAmount)).to.be.revertedWith("AbstractVault: Caller is not the vault manager");
    });
});
