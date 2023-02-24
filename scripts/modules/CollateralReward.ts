/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db } from "../utils";

async function main(proxyAdmin: string, caller: string, distributor: string, stakingToken: string, rewardToken: string) {
    const [deployer] = await ethers.getSigners();

    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const CollateralReward = await ethers.getContractFactory("CollateralReward", deployer);
    const collateralReward = await CollateralReward.deploy();
    const instance = await collateralReward.deployed();
    db.set(`CollateralReward`, instance.address);

    const data = instance.interface.encodeFunctionData("initialize", [caller, distributor, stakingToken, rewardToken]);
    const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin, data);

    const instanceProxy = await ethers.getContractAt("CollateralReward", proxy.address, deployer);
    db.set(`CollateralRewardProxy`, { logic: instanceProxy.address, data: data });

    return instanceProxy;
}

export { main };
