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

    it("Test #execute", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);
        await rewardTracker.execute();

        expect(rewardTracker.execute()).to.be.revertedWith("CreditRewardTracker: Incorrect duration");

        await rewardTracker.setDuration(0);
        await rewardTracker.execute();
    });

    it("Test #setPendingOwner", async () => {
        const [deployer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        expect(rewardTracker.setPendingOwner(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _owner cannot be 0x0");

        await rewardTracker.setPendingOwner(deployer.address);
        await rewardTracker.acceptOwner();
    });

    it("Test #addGovernor #addGovernors #removeGovernor", async () => {
        const [deployer, test1Signer, test2Signer] = await ethers.getSigners();

        const rewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

        expect(rewardTracker.addGovernor(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _newGovernor cannot be 0x0");

        await rewardTracker.addGovernor(test1Signer.address);
        await rewardTracker.addGovernors([test2Signer.address]);

        expect(rewardTracker.addGovernor(test2Signer.address)).to.be.revertedWith("CreditRewardTracker: _newGovernor is already governor");

        expect(rewardTracker.removeGovernor(ethers.constants.AddressZero)).to.be.revertedWith("CreditRewardTracker: _governor cannot be 0x0");
        await rewardTracker.removeGovernor(test2Signer.address);
        expect(rewardTracker.removeGovernor(test2Signer.address)).to.be.revertedWith("CreditRewardTracker: _governor is not a governor");
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
        expect(rewardTracker.execute()).to.be.revertedWith("NotAuthorized()");
    });
});
