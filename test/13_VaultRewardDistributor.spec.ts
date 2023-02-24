/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as ProxyAdmin } from "../scripts/modules/ProxyAdmin";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { main as VaultRewardDistributor } from "../scripts/modules/VaultRewardDistributor";
import { main as SimpleProxy } from "../scripts/modules/SimpleProxy";
import { loadFixture } from "ethereum-waffle";
import { MockToken, WETH9, VaultRewardDistributor as VaultRewardDistributorInterface, BaseReward as BaseRewardInterface } from "../typechain";
import { deployMockTokens } from "./LoadFixture";
import { SimpleProxy as SimpleProxyInterface } from "../typechain/SimpleProxy";

async function deployProxyAdmin() {
    const proxyAdmin = await ProxyAdmin();

    return { proxyAdmin };
}

describe("VaultRewardDistributor contract", () => {
    let usdt: MockToken;
    let weth: WETH9;
    let simpleProxy: SimpleProxyInterface;
    let supplyBaseReward: BaseRewardInterface;
    let borrowedBaseReward: BaseRewardInterface;
    let vaultRewardDistributor: VaultRewardDistributorInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const mockTokens = await loadFixture(deployMockTokens);

        usdt = mockTokens.usdt;
        weth = mockTokens.weth;

        simpleProxy = await SimpleProxy(deployer.address);
        vaultRewardDistributor = await VaultRewardDistributor(
            proxyAdmin.address,
            simpleProxy.address,
            deployer.address,
            usdt.address,
            weth.address,
            "VaultRewardDistributor"
        );

        supplyBaseReward = await BaseReward(proxyAdmin.address, simpleProxy.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "Supply");
        borrowedBaseReward = await BaseReward(proxyAdmin.address, simpleProxy.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "Borrowed");
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const VaultRewardDistributor = await ethers.getContractFactory("VaultRewardDistributor", deployer);
        const vaultRewardDistributor = await VaultRewardDistributor.deploy();
        const instance = await vaultRewardDistributor.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, deployer.address, usdt.address, weth.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _staker cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, ethers.constants.AddressZero, usdt.address, weth.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _distributor cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, deployer.address, ethers.constants.AddressZero, weth.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _stakingToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, deployer.address, usdt.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _rewardToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, usdt.address, weth.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _staker is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, deployer.address, deployer.address, weth.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _stakingToken is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [simpleProxy.address, deployer.address, usdt.address, deployer.address])
            )
        ).to.be.revertedWith("VaultRewardDistributor: _rewardToken is not a contract");
    });

    it("Test #setSupplyRewardPoolRatio #setBorrowedRewardPool", async () => {
        await vaultRewardDistributor.setSupplyRewardPoolRatio(0);

        expect(await vaultRewardDistributor.supplyRewardPoolRatio()).to.be.eql(BigNumber.from(0));
        expect(await vaultRewardDistributor.borrowedRewardPoolRatio()).to.be.eql(BigNumber.from(1000));

        await vaultRewardDistributor.setBorrowedRewardPoolRatio(500);

        expect(await vaultRewardDistributor.supplyRewardPoolRatio()).to.be.eql(BigNumber.from(500));
        expect(await vaultRewardDistributor.borrowedRewardPoolRatio()).to.be.eql(BigNumber.from(500));

        expect(vaultRewardDistributor.setSupplyRewardPoolRatio(1001)).to.be.revertedWith("VaultRewardDistributor: Maximum limit exceeded");
        expect(vaultRewardDistributor.setBorrowedRewardPoolRatio(1001)).to.be.revertedWith("VaultRewardDistributor: Maximum limit exceeded");
    });

    it("Test #setSupplyRewardPool #setBorrowedRewardPool", async () => {
        expect(vaultRewardDistributor.setSupplyRewardPool(ethers.constants.AddressZero)).to.be.revertedWith(
            "VaultRewardDistributor: _rewardPool cannot be 0x0"
        );
        expect(vaultRewardDistributor.setBorrowedRewardPool(ethers.constants.AddressZero)).to.be.revertedWith(
            "VaultRewardDistributor: _rewardPool cannot be 0x0"
        );
        await vaultRewardDistributor.setSupplyRewardPool(supplyBaseReward.address);
        await vaultRewardDistributor.setBorrowedRewardPool(borrowedBaseReward.address);
        expect(vaultRewardDistributor.setSupplyRewardPool(supplyBaseReward.address)).to.be.revertedWith(
            "VaultRewardDistributor: Cannot run this function twice"
        );
        expect(vaultRewardDistributor.setBorrowedRewardPool(borrowedBaseReward.address)).to.be.revertedWith(
            "VaultRewardDistributor: Cannot run this function twice"
        );
    });

    it("Test #stake #withdraw #distribute", async () => {
        const [deployer] = await ethers.getSigners();

        const mintedAmoutIn = ethers.utils.parseUnits("200", 6);
        const mintedDistributorAmoutIn = ethers.utils.parseUnits("200", 6);
        const stakedAmountIn = mintedAmoutIn.div(2);
        const wethRewards = ethers.utils.parseEther("2");

        await usdt.mint(simpleProxy.address, mintedAmoutIn);
        await usdt.mint(simpleProxy.address, mintedDistributorAmoutIn);

        await vaultRewardDistributor.setSupplyRewardPool(supplyBaseReward.address);
        await vaultRewardDistributor.setBorrowedRewardPool(borrowedBaseReward.address);

        await simpleProxy.execute(usdt.address, usdt.interface.encodeFunctionData("approve", [supplyBaseReward.address, mintedAmoutIn]));
        await simpleProxy.execute(usdt.address, usdt.interface.encodeFunctionData("approve", [borrowedBaseReward.address, mintedAmoutIn]));
        await simpleProxy.execute(usdt.address, usdt.interface.encodeFunctionData("approve", [vaultRewardDistributor.address, mintedDistributorAmoutIn]));

        await simpleProxy.execute(supplyBaseReward.address, supplyBaseReward.interface.encodeFunctionData("stakeFor", [deployer.address, stakedAmountIn]));
        await simpleProxy.execute(borrowedBaseReward.address, borrowedBaseReward.interface.encodeFunctionData("stakeFor", [deployer.address, stakedAmountIn]));

        expect(simpleProxy.execute(vaultRewardDistributor.address, vaultRewardDistributor.interface.encodeFunctionData("stake", [0]))).to.be.revertedWith(
            "Failed"
        );

        await simpleProxy.execute(vaultRewardDistributor.address, vaultRewardDistributor.interface.encodeFunctionData("stake", [mintedDistributorAmoutIn]));

        expect(await supplyBaseReward.balanceOf(deployer.address)).to.be.eql(BigNumber.from(stakedAmountIn));
        expect(await borrowedBaseReward.balanceOf(deployer.address)).to.be.eql(BigNumber.from(stakedAmountIn));

        await weth.deposit({ value: wethRewards });
        await weth.approve(vaultRewardDistributor.address, wethRewards);
        await vaultRewardDistributor.distribute(wethRewards);

        expect(vaultRewardDistributor.distribute(0)).to.be.revertedWith("VaultRewardDistributor: _rewards cannot be 0");

        expect(await weth.balanceOf(supplyBaseReward.address)).to.be.eql(BigNumber.from(wethRewards.div(2)));
        expect(await weth.balanceOf(borrowedBaseReward.address)).to.be.eql(BigNumber.from(wethRewards.div(2)));

        expect(await supplyBaseReward.pendingRewards(deployer.address)).to.be.above(BigNumber.from("0"));
        expect(await borrowedBaseReward.pendingRewards(deployer.address)).to.be.above(BigNumber.from("0"));

        expect(simpleProxy.execute(vaultRewardDistributor.address, vaultRewardDistributor.interface.encodeFunctionData("withdraw", [0]))).to.be.revertedWith(
            "Failed"
        );

        await simpleProxy.execute(vaultRewardDistributor.address, vaultRewardDistributor.interface.encodeFunctionData("withdraw", [mintedDistributorAmoutIn]));
    });

    it("Test #renounceOwnership", async () => {
        expect(vaultRewardDistributor.renounceOwnership()).to.be.revertedWith("VaultRewardDistributor: Not allowed");
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const mintedDistributorAmoutIn = ethers.utils.parseUnits("200", 6);

        await usdt.mint(simpleProxy.address, mintedDistributorAmoutIn);
        await usdt.approve(vaultRewardDistributor.address, mintedDistributorAmoutIn);

        expect(vaultRewardDistributor.stake(mintedDistributorAmoutIn)).to.be.revertedWith("VaultRewardDistributor: Caller is not the staker");

        const newVaultRewardDistributor = await vaultRewardDistributor.connect(wrongSigner);

        const wethRewards = ethers.utils.parseEther("2");
        await weth.deposit({ value: wethRewards });
        await weth.approve(vaultRewardDistributor.address, wethRewards);

        expect(newVaultRewardDistributor.distribute(wethRewards)).to.be.revertedWith("VaultRewardDistributor: Caller is not the distributor");
    });
});
