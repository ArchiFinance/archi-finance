/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { main as Base } from "./deploys/1_base";
import { main as Vault } from "./deploys/2_Vault";
import { main as Initialize } from "./deploys/3_initialize";
import { main as Ownership } from "./deploys/4_Ownership";

async function main() {
    const [deployer] = await ethers.getSigners();

    const balBefore = await ethers.provider.getBalance(deployer.address);
    console.log("deployer eth:", ethers.utils.formatEther(balBefore));

    await Base();
    await Vault();
    await Initialize();
    await Ownership();

    const balAfter = await ethers.provider.getBalance(deployer.address);
    console.log("deployer eth: ", ethers.utils.formatEther(balAfter));
    console.log("deployer eth spent:", ethers.utils.formatEther(balBefore.sub(balAfter)));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
