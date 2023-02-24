/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, owner: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditTokenMinter = await ethers.getContractFactory("CreditTokenMinter", deployer);
    const creditTokenMinter = await CreditTokenMinter.deploy();
    const instance = await creditTokenMinter.deployed();
    db.set(`CreditTokenMinter`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [owner]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditTokenMinter", proxy.address, deployer);
    db.set(`CreditTokenMinterProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
