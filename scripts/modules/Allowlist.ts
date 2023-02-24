/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main() {
    const [deployer] = await ethers.getSigners();
    const Allowlist = await ethers.getContractFactory("Allowlist", deployer);
    const allowlist = await Allowlist.deploy(false);
    const instance = await allowlist.deployed();
    db.set(`Allowlist`, instance.address);

    return instance;
}

export { main };
