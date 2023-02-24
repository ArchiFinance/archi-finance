/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, staker: string, distributor: string, stakingToken: string, rewardToken: string, name: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const VaultRewardDistributor = await ethers.getContractFactory("VaultRewardDistributor", deployer);
    const vaultRewardDistributor = await VaultRewardDistributor.deploy();
    const instance = await vaultRewardDistributor.deployed();
    db.set(`${name}VaultRewardDistributor`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [staker, distributor, stakingToken, rewardToken]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("VaultRewardDistributor", proxy.address, deployer);
    db.set(`${name}VaultRewardDistributorProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
