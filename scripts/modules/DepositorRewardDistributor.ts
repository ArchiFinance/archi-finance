/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, rewardToken: string, stakingToken: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const DepositorRewardDistributor = await ethers.getContractFactory("DepositorRewardDistributor", deployer);
    const depositorRewardDistributor = await DepositorRewardDistributor.deploy();
    const instance = await depositorRewardDistributor.deployed();
    db.set("DepositorRewardDistributor", instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [rewardToken, stakingToken]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("DepositorRewardDistributor", proxy.address, deployer);
    db.set("DepositorRewardDistributorProxy", { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
