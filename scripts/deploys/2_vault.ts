/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, MulticallTxs, TOKENS, waitTx } from "../utils";
import { main as ETHVault } from "../modules/ETHVault";
import { main as ERC20Vault } from "../modules/ERC20Vault";
import { main as CreditManager } from "../modules/CreditManager";
import { main as BaseReward } from "../modules/BaseReward";
import { main as VaultRewardDistributor } from "../modules/VaultRewardDistributor";
import { Signer } from "ethers";

const TX_CONFIRMATIONS_NUMBER = 1;

async function deployVault(deployer: Signer, tokenName: string, isPasued: boolean) {
    const proxyAdmin = await ethers.getContractAt("ProxyAdmin", db.get("ProxyAdmin"), deployer);
    const creditCaller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);
    const creditToken = await ethers.getContractAt("CreditToken", db.get("CreditToken"), deployer);
    const creditTokenStaker = await ethers.getContractAt("CreditTokenStaker", db.get("CreditTokenStakerProxy").logic, deployer);
    const depositorRewardDistributor = await ethers.getContractAt("DepositorRewardDistributor", db.get("DepositorRewardDistributorProxy").logic, deployer);
    const creditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);

    let isWrappedToken: boolean = false;
    let vault;

    if (tokenName === "WETH") {
        vault = await ETHVault(proxyAdmin.address, TOKENS[tokenName], tokenName);
        isWrappedToken = true;
    } else {
        vault = await ERC20Vault(proxyAdmin.address, TOKENS[tokenName], tokenName);
    }
    const vaultManager = await CreditManager(proxyAdmin.address, vault.address, creditCaller.address, creditRewardTracker.address, tokenName);
    const vaultRewardDistributor = await VaultRewardDistributor(
        proxyAdmin.address,
        creditTokenStaker.address,
        depositorRewardDistributor.address,
        creditToken.address,
        TOKENS.WETH,
        tokenName
    );
    const supplyRewardPool = await BaseReward(
        proxyAdmin.address,
        vault.address,
        vaultRewardDistributor.address,
        vault.address,
        TOKENS.WETH,
        `${tokenName}Supply`
    );
    const borrowedRewardPool = await BaseReward(
        proxyAdmin.address,
        vault.address,
        vaultRewardDistributor.address,
        vault.address,
        TOKENS.WETH,
        `${tokenName}Borrowed`
    );

    return {
        tokenName: tokenName,
        token: TOKENS[tokenName],
        vault: vault,
        vaultManager: vaultManager,
        supplyRewardPool: supplyRewardPool,
        borrowedRewardPool: borrowedRewardPool,
        vaultRewardDistributor: vaultRewardDistributor,
        isWrappedToken: isWrappedToken,
        depositorRewardDistributor: depositorRewardDistributor,
        creditRewardTracker: creditRewardTracker,
        paused: isPasued,
    };
}

async function updateContract(deployer: Signer, vault: any) {
    const vaultMC = new MulticallTxs(vault.vault, TX_CONFIRMATIONS_NUMBER);

    vaultMC
        .addEncodeFunctionData("setSupplyRewardPool", [vault.supplyRewardPool.address])
        .addEncodeFunctionData("setBorrowedRewardPool", [vault.borrowedRewardPool.address])
        .addEncodeFunctionData("addCreditManager", [vault.vaultManager.address])
        .addEncodeFunctionData("setRewardTracker", [vault.creditRewardTracker.address]);

    await waitTx([await vault.vaultRewardDistributor.setSupplyRewardPool(vault.supplyRewardPool.address)]);
    await waitTx([await vault.vaultRewardDistributor.setBorrowedRewardPool(vault.borrowedRewardPool.address)]);
    await waitTx([await vault.depositorRewardDistributor.addExtraReward(vault.vaultRewardDistributor.address)]);
    await waitTx([await vault.creditRewardTracker.toggleVaultCanExecute(vault.vault.address)]);

    if (vault.isWrappedToken) {
        vaultMC.addEncodeFunctionData("setWrappedToken", [TOKENS.WETH]);
    }

    if (vault.paused) {
        vaultMC.addEncodeFunctionData("pause");
    }

    await vaultMC.waitTx();
}

async function main(vaults?: any) {
    const [deployer] = await ethers.getSigners();

    const results: any = [];
    const tasks: any = [];

    if (vaults === undefined) {
        for (const v in TOKENS) tasks.push(await deployVault(deployer, v, false));
    } else {
        for (const v of vaults) tasks.push(await deployVault(deployer, v.tokenName, v.isPasued));
    }

    await Promise.all(tasks).then(async (values) => {
        for (const idx in values) {
            await updateContract(deployer, values[idx]);
            results.push(values[idx]);
        }
    });

    if (results.length > 0) {
        const creditCaller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);
        const depositor = await ethers.getContractAt("GMXDepositor", db.get("GMXDepositorProxy").logic, deployer);
        const collateralReward = await ethers.getContractAt("CollateralReward", db.get("CollateralRewardProxy").logic, deployer);
        const multicallTxs = new MulticallTxs(creditCaller, TX_CONFIRMATIONS_NUMBER);

        const strategy: any = {
            depositor: depositor.address,
            collateralReward: collateralReward.address,
            vaults: [],
            vaultRewards: [],
        };

        for (const idx in results) {
            strategy.vaults.push(results[idx].vault.address);
            strategy.vaultRewards.push(results[idx].vaultRewardDistributor.address);
        }

        multicallTxs.addEncodeFunctionData("addStrategy", [strategy.depositor, strategy.collateralReward, strategy.vaults, strategy.vaultRewards]);

        for (const idx in results) {
            multicallTxs.addEncodeFunctionData("addVaultManager", [results[idx].token, results[idx].vaultManager.address]);
        }

        await multicallTxs.waitTx();
    }
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
