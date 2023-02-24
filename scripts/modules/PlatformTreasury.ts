/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(operator: string) {
    const [deployer] = await ethers.getSigners();

    const PlatformTreasury = await ethers.getContractFactory("PlatformTreasury", deployer);
    const platformTreasury = await PlatformTreasury.deploy(operator);
    const instance = await platformTreasury.deployed();
    db.set(`PlatformTreasury`, instance.address);

    return instance;
}

export { main };
