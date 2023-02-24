/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { ShareLocker as ShareLockerInferface } from "../typechain";
import { deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { loadFixture } from "ethereum-waffle";
import { MockToken as MockTokenInterface } from "../typechain/MockToken";
import { BaseReward as BaseRewardInterface } from "../typechain/BaseReward";
import { SimpleProxy as SimpleProxyInterface } from "../typechain/SimpleProxy";
import { removeDb } from "../scripts/utils";

describe("ShareLocker contract", () => {
    const mintedAmount = ethers.utils.parseUnits("100", 18);
    let baseReward: BaseRewardInterface;
    let shareLocker: ShareLockerInferface;
    let mockToken: MockTokenInterface;
    let simpleProxy: SimpleProxyInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { weth } = await loadFixture(deployMockTokens);

        const MockToken = await ethers.getContractFactory("MockToken", deployer);
        mockToken = await (await MockToken.deploy("Mock token", "MT", 18)).deployed();

        const SimpleProxy = await ethers.getContractFactory("SimpleProxy", deployer);
        simpleProxy = await (await SimpleProxy.deploy(deployer.address)).deployed();

        baseReward = await BaseReward(proxyAdmin.address, deployer.address, deployer.address, mockToken.address, weth.address, "MOCK ShareLocker");

        const ShareLocker = await ethers.getContractFactory("ShareLocker", deployer);
        shareLocker = await (await ShareLocker.deploy(simpleProxy.address, simpleProxy.address, baseReward.address)).deployed();
    });

    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const ShareLocker = await ethers.getContractFactory("ShareLocker", deployer);

        expect(ShareLocker.deploy(ethers.constants.AddressZero, simpleProxy.address, baseReward.address)).to.be.revertedWith(
            "ShareLocker: _vault cannot be 0x0"
        );
        expect(ShareLocker.deploy(simpleProxy.address, ethers.constants.AddressZero, baseReward.address)).to.be.revertedWith(
            "ShareLocker: _creditManager cannot be 0x0"
        );
        expect(ShareLocker.deploy(simpleProxy.address, simpleProxy.address, ethers.constants.AddressZero)).to.be.revertedWith(
            "ShareLocker: _rewardPool cannot be 0x0"
        );

        expect(ShareLocker.deploy(deployer.address, simpleProxy.address, baseReward.address)).to.be.revertedWith("ShareLocker: _vault is not a contract");
        expect(ShareLocker.deploy(simpleProxy.address, deployer.address, baseReward.address)).to.be.revertedWith(
            "ShareLocker: _creditManager is not a contract"
        );
        expect(ShareLocker.deploy(simpleProxy.address, simpleProxy.address, deployer.address)).to.be.revertedWith("ShareLocker: _rewardPool is not a contract");
    });

    it("Test #stake", async () => {
        await mockToken.mockApprove(shareLocker.address, baseReward.address, mintedAmount);
        await mockToken.mint(shareLocker.address, mintedAmount);

        expect(shareLocker.stake(mintedAmount)).to.be.revertedWith("ShareLocker: Caller is not the vault");

        await simpleProxy.execute(shareLocker.address, shareLocker.interface.encodeFunctionData("stake", [mintedAmount]));
    });

    it("Test #withdraw", async () => {
        await mockToken.mockApprove(shareLocker.address, baseReward.address, mintedAmount);
        await mockToken.mint(shareLocker.address, mintedAmount);

        await simpleProxy.execute(shareLocker.address, shareLocker.interface.encodeFunctionData("stake", [mintedAmount]));
        await simpleProxy.execute(shareLocker.address, shareLocker.interface.encodeFunctionData("withdraw", [mintedAmount]));
    });

    it("Test #harvest", async () => {
        const { weth } = await loadFixture(deployMockTokens);
        const mintedRewards = ethers.utils.parseEther("1");

        await weth.approve(baseReward.address, mintedRewards);
        await weth.deposit({ value: mintedRewards });

        await mockToken.mockApprove(shareLocker.address, baseReward.address, mintedAmount);
        await mockToken.mint(shareLocker.address, mintedAmount);

        await simpleProxy.execute(shareLocker.address, shareLocker.interface.encodeFunctionData("stake", [mintedAmount]));
        await baseReward.distribute(mintedRewards);
        await simpleProxy.execute(shareLocker.address, shareLocker.interface.encodeFunctionData("harvest"));

        expect(shareLocker.harvest()).to.be.revertedWith("ShareLocker: Caller is not the credit manager");
    });

    it("Test #pendingRewards", async () => {
        expect(await shareLocker.pendingRewards()).to.be.eq(BigNumber.from(0));
    });
});
