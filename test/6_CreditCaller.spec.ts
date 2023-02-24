/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { db, increaseDays, increaseMinutes, removeDb, sleep, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as Base } from "../scripts/deploys/1_base";
import { main as Vault } from "../scripts/deploys/2_vault";
import { main as Initial } from "../scripts/deploys/3_initialize";
import { loadFixture } from "ethereum-waffle";
import { deployAddressProvider, deployMockTokens, deployProxyAdmin } from "./LoadFixture";

const ZERO = `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`;

async function _swapToken(toToken: string, ethAmountIn: BigNumber) {
    const [deployer] = await ethers.getSigners();
    const gmxRouter = await ethers.getContractAt(require("../scripts/abis/GmxRoute"), "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064", deployer);

    await gmxRouter.swapETHToTokens([TOKENS.WETH, toToken], 0, deployer.address, { value: ethAmountIn });
}

describe("CreditCaller & CreditManager contract", () => {
    beforeEach(async () => {
        await Base();
        await Vault();
        await Initial();
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { addressProvider } = await loadFixture(deployAddressProvider);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const CreditCaller = await ethers.getContractFactory("CreditCaller", deployer);
        const creditCaller = await CreditCaller.deploy();
        const instance = await creditCaller.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, TOKENS.WETH])
            )
        ).to.be.revertedWith("CreditCaller: _addressProvider cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [addressProvider.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditCaller: _wethAddress cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, TOKENS.WETH])
            )
        ).to.be.revertedWith("CreditCaller: _addressProvider is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [addressProvider.address, deployer.address])
            )
        ).to.be.revertedWith("CreditCaller: _wethAddress is not a contract");
    });

    it("Test ETH #openLendCredit #repayCredit #liquidate", async () => {
        const [deployer, illegalSigner] = await ethers.getSigners();
        const { weth } = await loadFixture(deployMockTokens);

        const vault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");

        await vault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await weth.deposit({ value: collateralAmountIn });
        await weth.approve(caller.address, collateralAmountIn);

        const depositer = db.get("GMXDepositorProxy").logic;

        expect(caller.openLendCredit(depositer, ethers.constants.AddressZero, collateralAmountIn, [TOKENS.WETH], [400], deployer.address)).to.be.revertedWith(
            "CreditCaller: _token cannot be 0x0"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, 0, [TOKENS.WETH], [400], deployer.address)).to.be.revertedWith(
            "CreditCaller: _amountIn cannot be 0"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [], deployer.address)).to.be.revertedWith(
            "CreditCaller: _ratios cannot be empty"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [99], deployer.address)).to.be.revertedWith(
            "CreditCaller: MIN_RATIO limit exceeded"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [1001], deployer.address)).to.be.revertedWith(
            "CreditCaller: MAX_RATIO limit exceeded"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [400, 500], deployer.address)).to.be.revertedWith(
            "CreditCaller: Length mismatch"
        );

        expect(
            caller.openLendCredit(depositer, ZERO, collateralAmountIn.mul(2), [TOKENS.WETH], [400], deployer.address, { value: collateralAmountIn })
        ).to.be.revertedWith("CreditCaller: ETH amount mismatch");

        expect(
            caller.openLendCredit(depositer, ZERO, collateralAmountIn, [TOKENS.WETH], [400], illegalSigner.address, { value: collateralAmountIn })
        ).to.be.revertedWith("CreditCaller: Not whitelisted");

        await caller.openLendCredit(depositer, ZERO, collateralAmountIn, [TOKENS.WETH], [400], deployer.address, { value: collateralAmountIn });

        await caller.setAllowlist(ethers.constants.AddressZero);

        await caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [400], deployer.address);

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        expect(creditCounts).to.be.above(BigNumber.from("0"));
        expect(caller.repayCredit(0)).to.be.revertedWith("CreditCaller: Minimum limit exceeded");
        expect(caller.repayCredit(creditCounts.add(1))).to.be.revertedWith("CreditCaller: Index out of range");

        expect(caller.liquidate(deployer.address, 0)).to.be.revertedWith("CreditCaller: Minimum limit exceeded");
        expect(caller.liquidate(deployer.address, creditCounts.add(1))).to.be.revertedWith("CreditCaller: Index out of range");

        const creditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        await creditRewardTracker.execute();

        await increaseMinutes(120);

        await caller.liquidate(deployer.address, creditCounts);
        await caller.repayCredit(creditCounts);

        const manager = await ethers.getContractAt("CreditManager", db.get("WETHVaultManagerProxy").logic, deployer);

        await manager.balanceOf(deployer.address);
        await manager.pendingRewards(deployer.address);
        await manager.claim(deployer.address);

        expect(manager.borrow(deployer.address, 0)).to.be.revertedWith("CreditManager: Caller is not the caller");
        expect(manager.harvest()).to.be.revertedWith("CreditManager: Caller is not the reward tracker");
    });

    it("Test strategy", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const collateralAmountIn = ethers.utils.parseEther("1");

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const Depositor = await ethers.getContractFactory("GMXDepositor", deployer);
        const depositor = await Depositor.deploy();
        const instance = await depositor.deployed();

        const data = instance.interface.encodeFunctionData("initialize", [db.get("CreditCallerProxy").logic, TOKENS.WETH, db.get("CreditRewardTrackerProxy").logic, deployer.address]);
        const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin.address, data);

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.openLendCredit(proxy.address, ZERO, collateralAmountIn, [TOKENS.WETH], [200], deployer.address, { value: collateralAmountIn })).to.be.revertedWith(
            "CreditCaller: Mismatched strategy"
        );
    });

    it("Test #calcHealth", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await caller.calcHealth(BigNumber.from("100"), BigNumber.from("200"), BigNumber.from("500"));
        await caller.calcHealth(BigNumber.from("200"), BigNumber.from("100"), BigNumber.from("500"));
    });

    it("Test #claimFor", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await caller.claimFor(db.get("CollateralRewardProxy").logic, deployer.address);
    });

    it("Test #setCreditUser", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setCreditUser(ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditUser cannot be 0x0");
        expect(caller.setCreditUser(db.get("CreditUserProxy").logic)).to.be.revertedWith("CreditCaller: Cannot run this function twice");
    });

    it("Test #setCreditTokenStaker", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setCreditTokenStaker(ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditTokenStaker cannot be 0x0");
        expect(caller.setCreditTokenStaker(db.get("CreditTokenStakerProxy").logic)).to.be.revertedWith("CreditCaller: Cannot run this function twice");
    });

    it("Test #addVaultManager", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.addVaultManager(ethers.constants.AddressZero, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith("CreditCaller: _underlyingToken cannot be 0x0");
        expect(caller.addVaultManager(TOKENS.WETH, ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditManager cannot be 0x0");
        expect(caller.addVaultManager(TOKENS.WETH, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith("CreditCaller: Not allowed");
    });

    it("Test #addVaultManager", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.addVaultManager(ethers.constants.AddressZero, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith("CreditCaller: _underlyingToken cannot be 0x0");
        expect(caller.addVaultManager(TOKENS.WETH, ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditManager cannot be 0x0");
        expect(caller.addVaultManager(TOKENS.WETH, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith("CreditCaller: Not allowed");
    });

    it("Test #addStrategy", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        const depositer = db.get("GMXDepositorProxy").logic;
        const collateralReward = db.get("CollateralRewardProxy").logic;
        const vaults: Array<string> = [];
        const vaultRewards: Array<string> = [];

        expect(caller.addStrategy(ethers.constants.AddressZero, collateralReward, vaults, vaultRewards)).to.be.revertedWith(
            "CreditCaller: _depositor cannot be 0x0"
        );

        expect(caller.addStrategy(depositer, ethers.constants.AddressZero, vaults, vaultRewards)).to.be.revertedWith(
            "CreditCaller: _collateralReward cannot be 0x0"
        );

        vaults.push(db.get("WETHVaultProxy").logic);

        expect(caller.addStrategy(depositer, collateralReward, vaults, vaultRewards)).to.be.revertedWith("CreditCaller: Length mismatch");
    });

    it("Test #renounceOwnership", async () => {
        const [deployer] = await ethers.getSigners();
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.renounceOwnership()).to.be.revertedWith("CreditCaller: Not allowed");
    });
});
