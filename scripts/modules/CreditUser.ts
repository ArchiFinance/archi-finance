/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, caller: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditUser = await ethers.getContractFactory("CreditUser", deployer);
    const creditUser = await CreditUser.deploy();
    const instance = await creditUser.deployed();
    db.set(`CreditUser`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [caller]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditUser", proxy.address, deployer);
    db.set(`CreditUserProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
