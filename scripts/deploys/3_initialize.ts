/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, TOKENS, waitTx } from "../utils";

async function main() {
    const [deployer] = await ethers.getSigners();

    const CreditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);
    const GMXDepositor = await ethers.getContractAt("GMXDepositor", db.get("GMXDepositorProxy").logic, deployer);

    for (const tokenName in TOKENS) {
        const vaultManager = db.get(`${tokenName}VaultManagerProxy`);

        if (vaultManager !== undefined) {
            const vaultManagerInstance = await ethers.getContractAt("CreditManager", vaultManager.logic, deployer);

            await waitTx([await CreditRewardTracker.addManager(vaultManagerInstance.address)]);
        }
    }

    await waitTx([await CreditRewardTracker.addDepositor(GMXDepositor.address)]);
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
