/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main() {
    const [deployer] = await ethers.getSigners();

    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", deployer);
    const proxyAdmin = await ProxyAdmin.deploy();
    const instance = await proxyAdmin.deployed();
    db.set("ProxyAdmin", instance.address);

    return instance;
}

export { main };
