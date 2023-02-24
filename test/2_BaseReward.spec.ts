/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { loadFixture } from "ethereum-waffle";
import { deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { BaseReward as BaseRewardInterface } from "../typechain/BaseReward";
import { removeDb } from "../scripts/utils";

describe("BaseReward contract", () => {
    let baseReward: BaseRewardInterface;
    const PRECISION = ethers.utils.parseEther("1");
    const mintedRewards = ethers.utils.parseEther("1");
    const mintedAmount = ethers.utils.parseUnits("100", 6);

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { usdt, weth } = await loadFixture(deployMockTokens);

        baseReward = await BaseReward(proxyAdmin.address, deployer.address, deployer.address, usdt.address, weth.address, "MOCK");
    });

    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { usdt, weth } = await loadFixture(deployMockTokens);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const BaseReward = await ethers.getContractFactory("BaseReward", deployer);
        const baseReward = await BaseReward.deploy();
        const instance = await baseReward.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, deployer.address, usdt.address, weth.address])
            )
        ).to.be.revertedWith("BaseReward: _operator cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, ethers.constants.AddressZero, usdt.address, weth.address])
            )
        ).to.be.revertedWith("BaseReward: _distributor cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, ethers.constants.AddressZero, weth.address])
            )
        ).to.be.revertedWith("BaseReward: _stakingToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, usdt.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("BaseReward: _rewardToken cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, deployer.address, weth.address])
            )
        ).to.be.revertedWith("BaseReward: _stakingToken is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, usdt.address, deployer.address])
            )
        ).to.be.revertedWith("BaseReward: _rewardToken is not a contract");
    });

    it("Test #distribute when the test total supply is equal to 0", async () => {
        const { weth } = await loadFixture(deployMockTokens);

        await weth.approve(baseReward.address, mintedRewards);
        await weth.deposit({ value: mintedRewards });

        await baseReward.distribute(mintedRewards);

        expect(await baseReward.queuedRewards()).to.be.above(BigNumber.from(0));
    });

    it("Test #stakeFor", async () => {
        const [deployer] = await ethers.getSigners();
        const { usdt } = await loadFixture(deployMockTokens);

        await usdt.mint(deployer.address, mintedAmount);
        await usdt.approve(baseReward.address, mintedAmount);
        expect(baseReward.stakeFor(deployer.address, mintedAmount))
            .to.be.emit(baseReward, "StakeFor")
            .withArgs(deployer.address, mintedAmount, mintedAmount, mintedAmount);

        expect(baseReward.stakeFor(deployer.address, 0)).to.be.revertedWith("BaseReward: _amountIn cannot be 0");
        expect(baseReward.stakeFor(ethers.constants.AddressZero, mintedAmount)).to.be.revertedWith("BaseReward: _recipient cannot be 0x0");

        expect(await baseReward.balanceOf(deployer.address)).to.be.eq(BigNumber.from(mintedAmount));
        expect(await baseReward.pendingRewards(deployer.address)).to.be.eq(BigNumber.from(0));
        expect(await baseReward.accRewardPerShare()).to.be.eq(BigNumber.from(0));

        const user = await baseReward.users(deployer.address);

        expect(user.totalUnderlying).to.be.eq(BigNumber.from(mintedAmount));
        expect(user.rewards).to.be.eq(BigNumber.from(0));
        expect(user.rewardPerSharePaid).to.be.eq(BigNumber.from(0));

        expect(await baseReward.callStatic.claim(deployer.address)).to.be.eq(BigNumber.from(0));
    });

    it("Test #withdraw", async () => {
        const [deployer] = await ethers.getSigners();
        const { usdt } = await loadFixture(deployMockTokens);

        await usdt.mint(deployer.address, mintedAmount);
        await usdt.approve(baseReward.address, mintedAmount);

        const recipient = deployer.address;
        const amountOut = mintedAmount.div(2);
        const totalSupply = mintedAmount.div(2);
        const totalUnderlying = mintedAmount.div(2);

        await baseReward.stakeFor(deployer.address, mintedAmount);

        expect(baseReward.withdraw(mintedAmount.mul(2))).to.be.revertedWith("BaseReward: Insufficient amounts");
        expect(baseReward.withdraw(0)).to.be.revertedWith("BaseReward: _amountOut cannot be 0");
        expect(baseReward.withdrawFor(ethers.constants.AddressZero, mintedAmount)).to.be.revertedWith("BaseReward: _recipient cannot be 0x0");

        expect(baseReward.withdraw(amountOut)).to.be.emit(baseReward, "Withdraw").withArgs(recipient, amountOut, totalSupply, totalUnderlying);
        expect(baseReward.withdrawFor(deployer.address, amountOut))
            .to.be.emit(baseReward, "Withdraw")
            .withArgs(recipient, amountOut, BigNumber.from(0), BigNumber.from(0));

        expect(await baseReward.balanceOf(deployer.address)).to.be.eq(BigNumber.from(0));
    });

    it("Test totalSupply Execute distribute under normal conditions", async () => {
        const [deployer] = await ethers.getSigners();
        const { usdt, weth } = await loadFixture(deployMockTokens);

        await usdt.mint(deployer.address, mintedAmount);
        await usdt.approve(baseReward.address, mintedAmount);
        await baseReward.stakeFor(deployer.address, mintedAmount);

        await weth.approve(baseReward.address, mintedRewards);
        await weth.deposit({ value: mintedRewards });

        const accRewardPerShare = mintedRewards.mul(BigNumber.from(PRECISION)).div(await baseReward.totalSupply());

        expect(baseReward.distribute(0)).to.be.revertedWith("BaseReward: _rewards cannot be 0");
        expect(baseReward.distribute(mintedRewards)).to.be.emit(baseReward, "Distribute").withArgs(mintedRewards, accRewardPerShare);

        expect(await baseReward.accRewardPerShare()).to.be.eq(BigNumber.from(accRewardPerShare));
        expect(await baseReward.queuedRewards()).to.be.eq(BigNumber.from(0));
        expect(await baseReward.pendingRewards(deployer.address)).to.be.above(BigNumber.from(0));

        await baseReward.claim(deployer.address);
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();
        const { usdt, weth } = await loadFixture(deployMockTokens);

        const newBaseReward = await baseReward.connect(wrongSigner);
        const newWeth = await weth.connect(wrongSigner);

        await usdt.mint(deployer.address, mintedAmount);
        await usdt.approve(newBaseReward.address, mintedAmount);

        await newWeth.approve(newBaseReward.address, mintedRewards);
        await newWeth.deposit({ value: mintedRewards });

        await baseReward.stakeFor(deployer.address, mintedAmount);

        expect(newBaseReward.withdrawFor(deployer.address, mintedAmount)).to.be.revertedWith("BaseReward: Caller is not the operator");
        expect(newBaseReward.distribute(mintedRewards)).to.be.revertedWith("BaseReward: Caller is not the distributor");
    });
});
