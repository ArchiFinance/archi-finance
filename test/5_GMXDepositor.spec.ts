/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { evmMine, evmSnapshotRun, increaseDays, removeDb } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as GMXDepositor } from "../scripts/modules/GMXDepositor";
import { main as GMXExecutor } from "../scripts/modules/GMXExecutor";
import { main as DepositorRewardDistributor } from "../scripts/modules/DepositorRewardDistributor";
import { loadFixture } from "ethereum-waffle";
import { deployAddressProvider, deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { IERC20, WETH9 } from "../typechain";
import { GMXDepositor as GMXDepositorInterface } from "../typechain/GMXDepositor";
import { GMXExecutor as GMXExecutorInterface } from "../typechain/GMXExecutor";
import { DepositorRewardDistributor as DepositorRewardDistributorInterface } from "../typechain/DepositorRewardDistributor";

describe("GMXDepositor contract", () => {
    const amountIn = ethers.utils.parseEther("100");
    let weth: WETH9;
    let fsGLP: IERC20;
    let usdt: IERC20;
    let depositor: GMXDepositorInterface;
    let executor: GMXExecutorInterface;
    let distributor: DepositorRewardDistributorInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { addressProvider } = await loadFixture(deployAddressProvider);
        const mockToken = await loadFixture(deployMockTokens);

        weth = mockToken.weth;
        fsGLP = mockToken.fsGLP;
        usdt = mockToken.usdt;

        depositor = await GMXDepositor(proxyAdmin.address, deployer.address, weth.address, deployer.address, ethers.constants.AddressZero);
        executor = await GMXExecutor(proxyAdmin.address, depositor.address, addressProvider.address, weth.address);
        distributor = await DepositorRewardDistributor(proxyAdmin.address, weth.address, usdt.address);
    });

    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer, platform] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const Depositor = await ethers.getContractFactory("GMXDepositor", deployer);
        const depositor = await Depositor.deploy();
        const instance = await depositor.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, weth.address, deployer.address, platform.address])
            )
        ).to.be.revertedWith("GMXDepositor: _caller cannot be 0x0");
        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, ethers.constants.AddressZero, deployer.address, platform.address])
            )
        ).to.be.revertedWith("GMXDepositor: _wethAddress cannot be 0x0");
        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, weth.address, ethers.constants.AddressZero, platform.address])
            )
        ).to.be.revertedWith("GMXDepositor: _rewardTracker cannot be 0x0");
        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, deployer.address, deployer.address, platform.address])
            )
        ).to.be.revertedWith("GMXDepositor: _wethAddress is not a contract");
    });

    it("Test #mint #withdraw #harvest", async () => {
        const [deployer, platform] = await ethers.getSigners();

        await depositor.setPlatform(platform.address);
        await depositor.setExecutor(executor.address);
        await depositor.setDistributer(distributor.address);
        await distributor.addDistributor(depositor.address);

        const fsGLPBalBefore = await fsGLP.balanceOf(executor.address);

        await weth.deposit({ value: amountIn });
        await weth.approve(depositor.address, amountIn);

        expect(depositor.mint(ethers.constants.AddressZero, amountIn)).to.be.revertedWith("GMXDepositor: _token cannot be 0x0");
        expect(depositor.mint(`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, amountIn.mul(2), { value: amountIn })).to.be.revertedWith(
            "GMXDepositor: ETH amount mismatch"
        );

        await depositor.mint(`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, amountIn, { value: amountIn });
        await depositor.mint(weth.address, amountIn);

        expect(await weth.balanceOf(depositor.address)).to.be.eql(BigNumber.from("0"));

        const fsGLPBalAfter = await fsGLP.balanceOf(executor.address);
        const fsGLPBal = fsGLPBalAfter.sub(fsGLPBalBefore);

        expect(fsGLPBal).to.be.above(BigNumber.from("0"));

        await evmSnapshotRun(async () => {
            await increaseDays(7);
            await evmMine();
            await depositor.harvest();
            await increaseDays(7);
            await evmMine();
        });

        await depositor.setPlatform(ethers.constants.AddressZero);
        await depositor.harvest();
        await depositor.withdraw(weth.address, fsGLPBal, 0);
    });

    it("Test #setDistributer", async () => {
        expect(depositor.setDistributer(ethers.constants.AddressZero)).to.be.revertedWith("GMXDepositor: _distributer cannot be 0x0");
        await depositor.setDistributer(distributor.address);
        expect(depositor.setDistributer(distributor.address)).to.be.revertedWith("GMXDepositor: Cannot run this function twice");
    });

    it("Test #setExecutor", async () => {
        expect(depositor.setExecutor(ethers.constants.AddressZero)).to.be.revertedWith("GMXDepositor: _executor cannot be 0x0");
        await depositor.setExecutor(executor.address);
        expect(depositor.setExecutor(executor.address)).to.be.revertedWith("GMXDepositor: Cannot run this function twice");
    });

    it("Test #setPlatform", async () => {
        await depositor.setPlatform(ethers.constants.AddressZero);
    });

    it("Test #setPlatformFee", async () => {
        expect(depositor.setPlatformFee(BigNumber.from("16"))).to.be.revertedWith("GMXDepositor: Maximum limit exceeded");

        await depositor.setPlatformFee(BigNumber.from("10"));
    });

    it("Test #renounceOwnership", async () => {
        expect(depositor.renounceOwnership()).to.be.revertedWith("GMXDepositor: Not allowed");
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const newDepositor = await depositor.connect(wrongSigner);

        await weth.deposit({ value: amountIn });
        await weth.approve(newDepositor.address, amountIn);

        expect(newDepositor.mint(weth.address, amountIn)).to.be.revertedWith("GMXDepositor: Caller is not the caller");
        expect(newDepositor.harvest()).to.be.revertedWith("GMXDepositor: Caller is not the reward tracker");
    });
});
