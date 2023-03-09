/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { evmMine, evmRevert, evmSnapshot, increaseDays, removeDb } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as GMXExecutor } from "../scripts/modules/GMXExecutor";
import { loadFixture } from "ethereum-waffle";
import { deployAddressProvider, deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { IERC20, WETH9 } from "../typechain";
import { GMXExecutor as GMXExecutorInterface } from "../typechain/GMXExecutor";
import { SimpleProxy as SimpleProxyInterface } from "../typechain/SimpleProxy";

describe("GMXExecutor contract", () => {
    const amountIn = ethers.utils.parseEther("100");
    let weth: WETH9;
    let fsGLP: IERC20;
    let simpleProxy: SimpleProxyInterface;
    let executor: GMXExecutorInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const mockToken = await loadFixture(deployMockTokens);
        const { addressProvider } = await loadFixture(deployAddressProvider);

        weth = mockToken.weth;
        fsGLP = mockToken.fsGLP;

        const SimpleProxy = await ethers.getContractFactory("SimpleProxy", deployer);
        simpleProxy = await (await SimpleProxy.deploy(deployer.address)).deployed();

        executor = await GMXExecutor(proxyAdmin.address, simpleProxy.address, addressProvider.address, weth.address);
    });

    after(async () => {
        removeDb();
    });

    it("Test #initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const GMXExecutor = await ethers.getContractFactory("GMXExecutor", deployer);
        const gmxExecutor = await GMXExecutor.deploy();
        const instance = await gmxExecutor.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, weth.address, instance.address])
            )
        ).to.be.revertedWith("GMXExecuter: _addressProvider cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [instance.address, ethers.constants.AddressZero, instance.address])
            )
        ).to.be.revertedWith("GMXExecuter: _wethAddress cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [instance.address, instance.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("GMXExecuter: _depositor cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, weth.address, instance.address])
            )
        ).to.be.revertedWith("GMXExecuter: _addressProvider is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [instance.address, deployer.address, instance.address])
            )
        ).to.be.revertedWith("GMXExecuter: _wethAddress is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [instance.address, weth.address, deployer.address])
            )
        ).to.be.revertedWith("GMXExecuter: _depositor is not a contract");
    });

    it("Test #mint #withdraw #claimRewards", async () => {
        // const [deployer] = await ethers.getSigners();

        await weth.deposit({ value: amountIn });
        await weth.transfer(simpleProxy.address, amountIn);

        const fsGLPBalBefore = await fsGLP.balanceOf(executor.address);

        await simpleProxy.execute(weth.address, weth.interface.encodeFunctionData("approve", [executor.address, amountIn]));
        await simpleProxy.execute(executor.address, executor.interface.encodeFunctionData("mint", [weth.address, amountIn]));

        const fsGLPBalAfter = await fsGLP.balanceOf(executor.address);
        const fsGLPBal = fsGLPBalAfter.sub(fsGLPBalBefore);

        expect(fsGLPBal).to.be.above(BigNumber.from("0"));

        const snapshotId = (await evmSnapshot()) as string;
        await increaseDays(7);
        await evmMine();
        await evmRevert(snapshotId);

        await simpleProxy.execute(executor.address, executor.interface.encodeFunctionData("claimRewards"));
        await simpleProxy.execute(executor.address, executor.interface.encodeFunctionData("withdraw", [weth.address, fsGLPBal, 0]));
    });

    it("Test modifiers", async () => {
        await weth.deposit({ value: amountIn });
        await weth.transfer(simpleProxy.address, amountIn);
        await weth.approve(executor.address, amountIn);

        expect(executor.mint(weth.address, amountIn)).to.be.revertedWith("GMXExecuter: Caller is not the depositor");
    });
});
