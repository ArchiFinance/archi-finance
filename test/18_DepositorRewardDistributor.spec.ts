/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { main as ProxyAdmin } from "../scripts/modules/ProxyAdmin";
import { main as VaultRewardDistributor } from "../scripts/modules/VaultRewardDistributor";
import { main as DepositorRewardDistributor } from "../scripts/modules/DepositorRewardDistributor";
import { main as SimpleProxy } from "../scripts/modules/SimpleProxy";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { loadFixture } from "ethereum-waffle";
import { deployMockTokens } from "./LoadFixture";
import { SimpleProxy as SimpleProxyInterface } from "../typechain/SimpleProxy";
import { DepositorRewardDistributor as DepositorRewardDistributorInterface } from "../typechain/DepositorRewardDistributor";
import { MockToken, WETH9 } from "../typechain";
import { removeDb } from "../scripts/utils";

async function deployProxyAdmin() {
    const proxyAdmin = await ProxyAdmin();

    return { proxyAdmin };
}

describe("DepositorRewardDistributor contract", () => {
    let usdt: MockToken;
    let weth: WETH9;
    let simpleProxy: SimpleProxyInterface;
    let distributor: DepositorRewardDistributorInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const mockTokens = await loadFixture(deployMockTokens);

        usdt = mockTokens.usdt;
        weth = mockTokens.weth;

        simpleProxy = await SimpleProxy(deployer.address);
        distributor = await DepositorRewardDistributor(proxyAdmin.address, weth.address, usdt.address);

        await distributor.addDistributor(deployer.address);

        for (let i = 1; i <= 12; i++) {
            const reward = await VaultRewardDistributor(
                proxyAdmin.address,
                simpleProxy.address,
                distributor.address,
                usdt.address,
                weth.address,
                `REWARD_${i}`
            );

            const supplyReward = await BaseReward(proxyAdmin.address, deployer.address, reward.address, usdt.address, weth.address, `SUPPLY_REWARD_${i}`);
            const borrowedReward = await BaseReward(proxyAdmin.address, deployer.address, reward.address, usdt.address, weth.address, `BORROWED_REWARD_${i}`);

            await reward.setSupplyRewardPool(supplyReward.address);
            await reward.setBorrowedRewardPool(borrowedReward.address);
            await distributor.addExtraReward(reward.address);
        }
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const DepositorRewardDistributor = await ethers.getContractFactory("DepositorRewardDistributor", deployer);
        const depositorRewardDistributor = await DepositorRewardDistributor.deploy();
        const instance = await depositorRewardDistributor.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, weth.address])
            )
        ).to.be.revertedWith("DepositorRewardDistributor: _rewardToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [usdt.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("DepositorRewardDistributor: _stakingToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, weth.address])
            )
        ).to.be.revertedWith("DepositorRewardDistributor: _rewardToken is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [usdt.address, deployer.address])
            )
        ).to.be.revertedWith("DepositorRewardDistributor: _stakingToken is not a contract");
    });

    it("Test #addExtraReward #extraRewardsLength #clearExtraRewards", async () => {
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        expect(distributor.addExtraReward(ethers.constants.AddressZero)).to.be.revertedWith("DepositorRewardDistributor: _reward cannot be 0x0");

        const reward13 = await VaultRewardDistributor(proxyAdmin.address, simpleProxy.address, distributor.address, usdt.address, weth.address, `REWARD_13`);
        expect(distributor.addExtraReward(reward13.address)).to.be.revertedWith("DepositorRewardDistributor: Maximum limit exceeded");

        const reward14 = await VaultRewardDistributor(proxyAdmin.address, simpleProxy.address, distributor.address, weth.address, weth.address, `REWARD_14`);
        expect(distributor.addExtraReward(reward14.address)).to.be.revertedWith("DepositorRewardDistributor: Mismatched staking token");

        const reward15 = await VaultRewardDistributor(proxyAdmin.address, simpleProxy.address, distributor.address, usdt.address, usdt.address, `REWARD_15`);
        expect(distributor.addExtraReward(reward15.address)).to.be.revertedWith("DepositorRewardDistributor: Mismatched reward token");

        const MAX_EXTRA_REWARDS_SIZE = 12;

        expect(await distributor.extraRewardsLength()).to.be.eq(BigNumber.from(MAX_EXTRA_REWARDS_SIZE));
        await distributor.clearExtraRewards();
    });

    it("Test #addDistributor #addDistributors #removeDistributor", async () => {
        const [deployer, test1Signer, test2Signer] = await ethers.getSigners();

        await distributor.addDistributor(test1Signer.address);
        expect(distributor.addDistributor(test1Signer.address)).to.be.revertedWith("DepositorRewardDistributor: _distributor is already distributor");
        expect(distributor.addDistributor(ethers.constants.AddressZero)).to.be.revertedWith("DepositorRewardDistributor: _distributor cannot be 0x0");

        await distributor.addDistributors([test2Signer.address]);
        await distributor.removeDistributor(test2Signer.address);

        expect(distributor.removeDistributor(ethers.constants.AddressZero)).to.be.revertedWith("DepositorRewardDistributor: _distributor cannot be 0x0");
        expect(distributor.removeDistributor(test2Signer.address)).to.be.revertedWith("DepositorRewardDistributor: _distributor is not the distributor");
    });

    it("Test #distribute", async () => {
        const wethRewards = ethers.utils.parseEther("2");
        await weth.deposit({ value: wethRewards });
        await weth.approve(distributor.address, wethRewards);

        expect(distributor.distribute(0)).to.be.revertedWith("VaultRewardDistributor: _rewards cannot be 0");

        await distributor.distribute(wethRewards.div(2));

        const reward0 = await distributor.extraRewards(0);
        await usdt.mint(reward0, ethers.utils.parseUnits("200", 6));

        await distributor.distribute(wethRewards.div(2));
    });

    it("Test #renounceOwnership", async () => {
        expect(distributor.renounceOwnership()).to.be.revertedWith("DepositorRewardDistributor: Not allowed");
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const wethRewards = ethers.utils.parseEther("2");
        await weth.deposit({ value: wethRewards });
        await weth.approve(distributor.address, wethRewards);

        const newDistributor = await distributor.connect(wrongSigner);

        expect(newDistributor.distribute(wethRewards)).to.be.revertedWith("DepositorRewardDistributor: Caller is not the distributor");
    });
});
