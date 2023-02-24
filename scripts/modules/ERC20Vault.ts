/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, underlyingToken: string, name: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const Vault = await ethers.getContractFactory("ERC20Vault", deployer);
    const vault = await Vault.deploy();
    const instance = await vault.deployed();
    db.set(`${name}Vault`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [underlyingToken]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("ERC20Vault", proxy.address, deployer);
    db.set(`${name}VaultProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
