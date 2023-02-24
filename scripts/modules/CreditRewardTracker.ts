/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, owner: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditRewardTracker = await ethers.getContractFactory("CreditRewardTracker", deployer);
    const creditRewardTracker = await CreditRewardTracker.deploy();
    const instance = await creditRewardTracker.deployed();
    db.set(`CreditRewardTracker`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [owner]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditRewardTracker", proxy.address, deployer);
    db.set(`CreditRewardTrackerProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
