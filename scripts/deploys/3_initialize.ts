/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, waitTx } from "../utils";

async function main() {
    const [deployer] = await ethers.getSigners();

    const CreditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

    const GMXDepositor = await ethers.getContractAt("GMXDepositor", db.get("GMXDepositorProxy").logic, deployer);
    const WETHVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("WETHVaultManagerProxy").logic, deployer);
    const USDTVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("USDTVaultManagerProxy").logic, deployer);
    const USDCVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("USDCVaultManagerProxy").logic, deployer);

    await waitTx([
        await CreditRewardTracker.addDepositor(GMXDepositor.address),
        await CreditRewardTracker.addManager(WETHVaultManagerProxy.address),
        await CreditRewardTracker.addManager(USDTVaultManagerProxy.address),
        await CreditRewardTracker.addManager(USDCVaultManagerProxy.address),
    ]);
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
