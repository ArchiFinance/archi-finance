/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main() {
    const [deployer] = await ethers.getSigners();

    const AddressProvider = await ethers.getContractFactory("AddressProvider", deployer);
    const addressProvider = await AddressProvider.deploy();
    const instance = await addressProvider.deployed();
    db.set(`AddressProvider`, instance.address);

    return instance;
}

export { main };
