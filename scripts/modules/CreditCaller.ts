/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, addressProvider: string, wethAddress: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CreditCaller = await ethers.getContractFactory("CreditCaller", deployer);
    const creditCaller = await CreditCaller.deploy();
    const instance = await creditCaller.deployed();
    db.set(`CreditCaller`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [addressProvider, wethAddress]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CreditCaller", proxy.address, deployer);
    db.set(`CreditCallerProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
