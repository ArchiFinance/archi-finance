/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, waitTx } from "../utils";
import { main as Timelock } from "../modules/Timelock";
import { main as SimpleProxy } from "../modules/SimpleProxy";

async function main() {
    const [deployer] = await ethers.getSigners();

    const timelock = await Timelock(deployer.address);
    const simpleProxy = await SimpleProxy(deployer.address);

    await waitTx([await simpleProxy.setPendingOwner(timelock.address)]);

    const AddressProvider = await ethers.getContractAt("AddressProvider", db.get("AddressProvider"), deployer);
    const CreditCaller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);
    const GMXDepositor = await ethers.getContractAt("GMXDepositor", db.get("GMXDepositorProxy").logic, deployer);
    const DepositorRewardDistributor = await ethers.getContractAt("DepositorRewardDistributor", db.get("DepositorRewardDistributorProxy").logic, deployer);
    const CreditTokenStaker = await ethers.getContractAt("CreditTokenStaker", db.get("CreditTokenStakerProxy").logic, deployer);
    const CreditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);
    // const CreditTokenMinter = await ethers.getContractAt("CreditTokenMinter", db.get("CreditTokenMinterProxy").logic, deployer);

    const WETHVaultProxy = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
    const WETHVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("WETHVaultRewardDistributorProxy").logic, deployer);

    const USDTVaultProxy = await ethers.getContractAt("ERC20Vault", db.get("USDTVaultProxy").logic, deployer);
    const USDTVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("USDTVaultRewardDistributorProxy").logic, deployer);

    const USDCVaultProxy = await ethers.getContractAt("ERC20Vault", db.get("USDCVaultProxy").logic, deployer);
    const USDCVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("USDCVaultRewardDistributorProxy").logic, deployer);

    // const WBTCVaultProxy = await ethers.getContractAt("ERC20Vault", db.get("WBTCVaultProxy").logic, deployer);
    // const WBTCVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("WBTCVaultManagerProxy").logic, deployer);
    // const WBTCVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("WBTCVaultRewardDistributorProxy").logic, deployer);

    // const DAIVaultProxy = await ethers.getContractAt("ERC20Vault", db.get("DAIVaultProxy").logic, deployer);
    // const DAIVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("DAIVaultManagerProxy").logic, deployer);
    // const DAIVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("DAIVaultRewardDistributorProxy").logic, deployer);

    // const FRAXVaultProxy = await ethers.getContractAt("ERC20Vault", db.get("FRAXVaultProxy").logic, deployer);
    // const FRAXVaultManagerProxy = await ethers.getContractAt("CreditManager", db.get("FRAXVaultManagerProxy").logic, deployer);
    // const FRAXVaultRewardDistributorProxy = await ethers.getContractAt("VaultRewardDistributor", db.get("FRAXVaultRewardDistributorProxy").logic, deployer);

    await waitTx([await CreditRewardTracker.setPendingOwner(simpleProxy.address)]);
    await waitTx([await CreditRewardTracker.acceptOwner()]);
    await waitTx([await AddressProvider.transferOwnership(simpleProxy.address)]);
    await waitTx([await CreditCaller.transferOwnership(simpleProxy.address)]);
    await waitTx([await GMXDepositor.transferOwnership(simpleProxy.address)]);
    await waitTx([await DepositorRewardDistributor.transferOwnership(simpleProxy.address)]);

    await waitTx([await CreditTokenStaker.addOwner(simpleProxy.address)]);
    await waitTx([await CreditTokenStaker.removeOwner(deployer.address)]);

    await waitTx([await WETHVaultProxy.transferOwnership(simpleProxy.address)]);
    await waitTx([await WETHVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    await waitTx([await USDTVaultProxy.transferOwnership(simpleProxy.address)]);
    await waitTx([await USDTVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    await waitTx([await USDCVaultProxy.transferOwnership(simpleProxy.address)]);
    await waitTx([await USDCVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    // await waitTx([await WBTCVaultProxy.transferOwnership(simpleProxy.address)]);
    // await waitTx([await WBTCVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    // await waitTx([await DAIVaultProxy.transferOwnership(simpleProxy.address)]);
    // await waitTx([await DAIVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    // await waitTx([await FRAXVaultProxy.transferOwnership(simpleProxy.address)]);
    // await waitTx([await FRAXVaultRewardDistributorProxy.transferOwnership(simpleProxy.address)]);

    // await simpleProxy.acceptOwner();
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
