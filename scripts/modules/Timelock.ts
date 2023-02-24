/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(admin: string) {
    const [deployer] = await ethers.getSigners();

    const Timelock = await ethers.getContractFactory("Timelock", deployer);
    const timelock = await Timelock.deploy(admin, 60 * 60 * 24 * 2);
    const instance = await timelock.deployed();
    db.set("Timelock", instance.address);

    return instance;
}

export { main };
