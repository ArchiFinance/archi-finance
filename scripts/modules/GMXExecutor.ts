/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, depositor: string, addressProvider: string, wethAddress: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const GMXExecutor = await ethers.getContractFactory("GMXExecutor", deployer);
    const gmxExecutor = await GMXExecutor.deploy();
    const instance = await gmxExecutor.deployed();
    db.set(`GMXExecutor`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [addressProvider, wethAddress, depositor]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("GMXExecutor", proxy.address, deployer);
    db.set(`GMXExecutorProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
