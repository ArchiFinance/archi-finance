/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, operator: string, distributor: string, stakingToken: string, rewardToken: string, name: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const BaseReward = await ethers.getContractFactory("BaseReward", deployer);
    const baseReward = await BaseReward.deploy();
    const instance = await baseReward.deployed();
    db.set(`${name}BaseReward`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [operator, distributor, stakingToken, rewardToken]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("BaseReward", proxy.address, deployer);
    db.set(`${name}BaseRewardProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
