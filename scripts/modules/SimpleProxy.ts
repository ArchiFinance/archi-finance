/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(owner: string) {
    const [deployer] = await ethers.getSigners();

    const SimpleProxy = await ethers.getContractFactory("SimpleProxy", deployer);
    const simpleProxy = await SimpleProxy.deploy(owner);
    const instance = await simpleProxy.deployed();
    db.set("SimpleProxy", instance.address);

    return instance;
}

export { main };
