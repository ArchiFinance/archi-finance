/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { db, removeDb } from "../scripts/utils";
import { main as Base } from "../scripts/deploys/1_base";
import { main as Vault } from "../scripts/deploys/2_vault";
import { main as Initial } from "../scripts/deploys/3_initialize";
import { loadFixture } from "ethereum-waffle";
import { deployProxyAdmin } from "./LoadFixture";

describe("CreditRewardTracker contract", () => {
    before(async () => {
        await Base();
        await Vault([
            { tokenName: "WETH", isPasued: false },
            { tokenName: "USDT", isPasued: false },
            { tokenName: "USDC", isPasued: false },
        ]);
        await Initial();
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const CreditRewardTracker = await ethers.getContractFactory("CreditRewardTracker", deployer);
        const creditRewardTracker = await CreditRewardTracker.deploy();
        const instance = await creditRewardTracker.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditRewardTracker: _owner cannot be 0x0");
    });

    it("Test #harvestDepositors #harvestManagers", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        await rewardTracker.harvestDepositors();
        await rewardTracker.harvestManagers();
    });

    it("Test #setPendingOwner", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        expect(rewardTracker.setPendingOwner(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _owner cannot be 0x0");
        expect(rewardTracker.acceptOwner()).to.be.revertedWith("CreditRewardTracker: pendingOwner cannot be 0x0");

        await rewardTracker.setPendingOwner(deployer.address);
        await rewardTracker.acceptOwner();
    });

    it("Test #toggleVaultCanExecute #execute", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        expect(rewardTracker.toggleVaultCanExecute(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _vault cannot be 0x0");

        await rewardTracker.toggleVaultCanExecute(deployer.address);
        await rewardTracker.execute();
    });

    it("Test #addManager #addDepositor", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        const prevManager = await rewardTracker.managers(0);

        expect(rewardTracker.addManager(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _manager cannot be 0x0");
        expect(rewardTracker.addManager(prevManager)).to.be.revertedWith("CreditRewardTracker: Duplicate _manager");

        const prevDepositor = await rewardTracker.depositors(0);

        expect(rewardTracker.addDepositor(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _depositor cannot be 0x0");
        expect(rewardTracker.addDepositor(prevDepositor)).to.be.revertedWith("CreditRewardTracker: Duplicate _depositor");

        const MAX_DEPOSITOR_SIZE = 8;
        const MAX_MANAGER_SIZE = 12;

        const managersLength = await rewardTracker.managersLength();

        for (let i = managersLength.toNumber(); i <= MAX_MANAGER_SIZE; i++) {
            const wallet = ethers.Wallet.createRandom().connect(ethers.provider);

            if (i === MAX_MANAGER_SIZE) {
                expect(rewardTracker.addManager(wallet.address)).to.be.revertedWith("CreditRewardTracker: Maximum limit exceeded");
            } else {
                await rewardTracker.addManager(wallet.address);
            }
        }

        const depositorsLength = await rewardTracker.depositorsLength();

        for (let i = depositorsLength.toNumber(); i <= MAX_DEPOSITOR_SIZE; i++) {
            const wallet = ethers.Wallet.createRandom().connect(ethers.provider);

            if (i === MAX_DEPOSITOR_SIZE) {
                expect(rewardTracker.addDepositor(wallet.address)).to.be.revertedWith("CreditRewardTracker: Maximum limit exceeded");
            } else {
                await rewardTracker.addDepositor(wallet.address);
            }
        }
    });

    it("Test #removeManager #removeDepositor", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        const managers = await rewardTracker.managersLength();
        expect(rewardTracker.removeManager(managers)).to.be.revertedWith("CreditRewardTracker: Index out of range");
        await rewardTracker.removeManager(managers.sub(1));

        const depositors = await rewardTracker.depositorsLength();
        expect(rewardTracker.removeDepositor(depositors)).to.be.revertedWith("CreditRewardTracker: Index out of range");
        await rewardTracker.removeDepositor(depositors.sub(1));
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, wrongSigner);

        expect(rewardTracker.setPendingOwner(deployer.address)).to.be.revertedWith("NotAuthorized()");
        expect(rewardTracker.execute()).to.be.revertedWith("CreditRewardTracker: Not allowed");
    });
});
