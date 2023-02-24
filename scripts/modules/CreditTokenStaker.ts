/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, owner: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditTokenStaker = await ethers.getContractFactory("CreditTokenStaker", deployer);
    const creditTokenStaker = await CreditTokenStaker.deploy();
    const instance = await creditTokenStaker.deployed();
    db.set(`CreditTokenStaker`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [owner]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditTokenStaker", proxy.address, deployer);
    db.set(`CreditTokenStakerProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
