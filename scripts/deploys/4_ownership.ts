/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, TOKENS, waitTx } from "../utils";
import { main as Timelock } from "../modules/Timelock";
import { main as SimpleProxy } from "../modules/SimpleProxy";

async function main() {
    const [deployer] = await ethers.getSigners();

    const timelock = await Timelock(deployer.address);
    const simpleProxy = await SimpleProxy(deployer.address);

    await waitTx([await simpleProxy.setPendingOwner(timelock.address)]);

    const addressProvider = await ethers.getContractAt("AddressProvider", db.get("AddressProvider"), deployer);
    const creditCaller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);
    const GMXDepositor = await ethers.getContractAt("GMXDepositor", db.get("GMXDepositorProxy").logic, deployer);
    const depositorRewardDistributor = await ethers.getContractAt("DepositorRewardDistributor", db.get("DepositorRewardDistributorProxy").logic, deployer);
    const creditTokenStaker = await ethers.getContractAt("CreditTokenStaker", db.get("CreditTokenStakerProxy").logic, deployer);
    const creditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

    await waitTx([await creditRewardTracker.setPendingOwner(simpleProxy.address)]);
    await waitTx([await creditRewardTracker.acceptOwner()]);
    await waitTx([await addressProvider.transferOwnership(simpleProxy.address)]);
    await waitTx([await creditCaller.transferOwnership(simpleProxy.address)]);
    await waitTx([await GMXDepositor.transferOwnership(simpleProxy.address)]);
    await waitTx([await depositorRewardDistributor.transferOwnership(simpleProxy.address)]);

    await waitTx([await creditTokenStaker.addOwner(simpleProxy.address)]);
    await waitTx([await creditTokenStaker.removeOwner(deployer.address)]);

    for (const tokenName in TOKENS) {
        const vault = db.get(`${tokenName}VaultProxy`);

        if (vault !== undefined) {
            const contractName = tokenName === "WETH" ? "ETHVault" : "ERC20Vault";

            const vaultInstance = await ethers.getContractAt(contractName, vault.logic, deployer);
            const vaultRewardDistributorInstance = await ethers.getContractAt(
                "VaultRewardDistributor",
                db.get(`${tokenName}VaultRewardDistributorProxy`).logic,
                deployer
            );

            await waitTx([await vaultInstance.transferOwnership(simpleProxy.address)]);
            await waitTx([await vaultRewardDistributorInstance.transferOwnership(simpleProxy.address)]);
        }
    }

    // await simpleProxy.acceptOwner();
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
