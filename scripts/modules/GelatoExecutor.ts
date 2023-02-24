/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(rewardTracker: string) {
    const [deployer] = await ethers.getSigners();

    const GelatoExecutor = await ethers.getContractFactory("GelatoExecutor", deployer);
    const executor = await GelatoExecutor.deploy(rewardTracker);
    const instance = await executor.deployed();
    db.set(`GelatoExecutor`, instance.address);

    return instance;
}

export { main };
