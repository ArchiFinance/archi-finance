/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { db, MulticallTxs, TOKENS, waitTx } from "../utils";
import { main as ProxyAdmin } from "../modules/ProxyAdmin";
import { main as PlatformTreasury } from "../modules/PlatformTreasury";
import { main as AddressProvider } from "../modules/AddressProvider";
import { main as CreditUser } from "../modules/CreditUser";
import { main as CreditCaller } from "../modules/CreditCaller";
import { main as CreditToken } from "../modules/CreditToken";
import { main as CreditTokenStaker } from "../modules/CreditTokenStaker";
import { main as CreditRewardTracker } from "../modules/CreditRewardTracker";
import { main as CollateralReward } from "../modules/CollateralReward";
import { main as Allowlist } from "../modules/Allowlist";
import { main as DepositorRewardDistributor } from "../modules/DepositorRewardDistributor";
import { main as GMXDepositor } from "../modules/GMXDepositor";
import { main as GMXExecutor } from "../modules/GMXExecutor";
import { main as CreditAggregator } from "../modules/CreditAggregator";

const TX_CONFIRMATIONS_NUMBER = 1;

async function getGmx() {
    const GMX: any = {
        rewardRouterV1: "0xa906f338cb21815cbc4bc87ace9e68c87ef8d8f1",
        rewardRouter: "0xB95DB5B167D75e6d04227CfFFA61069348d271F5",
        stakedGlp: "0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf",
        glpManager: ``,
        usdg: ``,
        vault: ``,
        priceFeed: ``,
        fsGlp: ``,
    };

    const gmxRewardRouter: any = await ethers.getContractAt(require("../abis/GmxRewardRouter"), GMX.rewardRouter);
    GMX.fsGlp = await gmxRewardRouter.callStatic.stakedGlpTracker();
    GMX.glpManager = await gmxRewardRouter.callStatic.glpManager();
    const glpManager: any = await ethers.getContractAt(require("../abis/GlpManager"), GMX.glpManager);
    GMX.vault = await glpManager.callStatic.vault();
    const vault: any = await ethers.getContractAt(require("../abis/GmxVault"), GMX.vault);
    GMX.usdg = await vault.callStatic.usdg();
    GMX.priceFeed = await vault.callStatic.priceFeed();

    return GMX;
}

async function main() {
    const [deployer] = await ethers.getSigners();

    const GMX = await getGmx();

    db.set("GMX", GMX);

    const platform = deployer.address;
    const proxyAdmin = await ProxyAdmin();
    const platformTreasury = await PlatformTreasury(platform);
    const addressProvider = await AddressProvider();

    const creditCaller = await CreditCaller(proxyAdmin.address, addressProvider.address, TOKENS.WETH);
    const creditUser = await CreditUser(proxyAdmin.address, creditCaller.address);
    const creditTokenStaker = await CreditTokenStaker(proxyAdmin.address, deployer.address);
    const creditToken = await CreditToken(creditTokenStaker.address, GMX.fsGlp);
    const creditRewardTracker = await CreditRewardTracker(proxyAdmin.address, deployer.address);

    const depositor = await GMXDepositor(proxyAdmin.address, creditCaller.address, TOKENS.WETH, creditRewardTracker.address, platformTreasury.address);
    const executor = await GMXExecutor(proxyAdmin.address, depositor.address, addressProvider.address, TOKENS.WETH);
    const creditAggregator = await CreditAggregator(proxyAdmin.address, addressProvider.address);

    const depositorRewardDistributor = await DepositorRewardDistributor(proxyAdmin.address, TOKENS.WETH, creditToken.address);
    const collateralReward = await CollateralReward(
        proxyAdmin.address,
        creditTokenStaker.address,
        depositorRewardDistributor.address,
        creditToken.address,
        TOKENS.WETH
    );

    const allowlist = await Allowlist();

    await waitTx([await allowlist.permit([deployer.address])]);
    await waitTx([await creditCaller.setAllowlist(allowlist.address)]);

    await waitTx([
        await creditTokenStaker.setCreditToken(creditToken.address),
        await creditTokenStaker.addOwner(creditCaller.address),
        //
        await addressProvider.setGmxRewardRouter(GMX.rewardRouter),
        await addressProvider.setGmxRewardRouterV1(GMX.rewardRouterV1),
        await addressProvider.setCreditAggregator(creditAggregator.address),
        await creditAggregator.update(),
    ]);

    await waitTx([await depositorRewardDistributor.addDistributor(depositor.address)]);
    await waitTx([await depositor.setDistributer(depositorRewardDistributor.address), await depositor.setExecutor(executor.address)]);
    await waitTx([await depositorRewardDistributor.addExtraReward(collateralReward.address)]);

    const creditCallerMC = new MulticallTxs(creditCaller, TX_CONFIRMATIONS_NUMBER);

    creditCallerMC.addEncodeFunctionData("setCreditUser", [creditUser.address]).addEncodeFunctionData("setCreditTokenStaker", [creditTokenStaker.address]);

    await creditCallerMC.waitTx();
}

export { main };

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
