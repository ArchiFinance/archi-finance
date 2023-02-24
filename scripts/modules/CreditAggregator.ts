/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, addressProvider: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const Liquidator = await ethers.getContractFactory("CreditAggregator", deployer);
    const liquidator = await Liquidator.deploy();
    const instance = await liquidator.deployed();
    db.set(`CreditAggregator`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [addressProvider]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditAggregator", proxy.address, deployer);
    db.set(`CreditAggregatorProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
