/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { loadFixture } from "ethereum-waffle";
import { deployProxyAdmin } from "./LoadFixture";
import { removeDb } from "../scripts/utils";

describe("CreditManager contract", () => {
    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const SimpleProxy = await ethers.getContractFactory("SimpleProxy", deployer);
        const simpleProxy = await (await SimpleProxy.deploy(deployer.address)).deployed();

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const CreditManager = await ethers.getContractFactory("CreditManager", deployer);
        const creditManager = await CreditManager.deploy();
        const instance = await creditManager.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, simpleProxy.address, simpleProxy.address])
            )
        ).to.be.revertedWith("CreditManager: _vault cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, ethers.constants.AddressZero, simpleProxy.address])
            )
        ).to.be.revertedWith("CreditManager: _caller cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, simpleProxy.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditManager: _rewardTracker cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, simpleProxy.address, simpleProxy.address])
            )
        ).to.be.revertedWith("CreditManager: _vault is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, deployer.address, simpleProxy.address])
            )
        ).to.be.revertedWith("CreditManager: _caller is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, simpleProxy.address, deployer.address])
            )
        ).to.be.revertedWith("CreditManager: _rewardTracker is not a contract");
    });
});
