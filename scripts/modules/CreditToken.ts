/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(operator: string, baseToken: string) {
    const [deployer] = await ethers.getSigners();

    const CreditToken = await ethers.getContractFactory("CreditToken", deployer);
    const creditToken = await CreditToken.deploy(operator, baseToken);
    const instance = await creditToken.deployed();
    db.set(`CreditToken`, instance.address);

    return instance;
}

export { main };
