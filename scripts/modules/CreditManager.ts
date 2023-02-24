/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, vault: string, caller: string, rewardTracker: string, name: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditManager = await ethers.getContractFactory("CreditManager", deployer);
    const creditManager = await CreditManager.deploy();
    const instance = await creditManager.deployed();
    db.set(`${name}VaultManager`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [vault, caller, rewardTracker]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditManager", proxy.address, deployer);
    db.set(`${name}VaultManagerProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
