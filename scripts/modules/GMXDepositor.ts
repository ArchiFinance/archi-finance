/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, caller: string, wethAddress: string, rewardTracker: string, platform: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const Depositor = await ethers.getContractFactory("GMXDepositor", deployer);
    const depositor = await Depositor.deploy();
    const instance = await depositor.deployed();
    db.set(`GMXDepositor`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [caller, wethAddress, rewardTracker, platform]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("GMXDepositor", proxy.address, deployer);
    db.set(`GMXDepositorProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
