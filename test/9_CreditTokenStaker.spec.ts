/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as BaseReward } from "../scripts/modules/BaseReward";
import { main as CollateralReward } from "../scripts/modules/CollateralReward";
import { main as VaultRewardDistributor } from "../scripts/modules/VaultRewardDistributor";
import { main as CreditTokenStaker } from "../scripts/modules/CreditTokenStaker";
import { loadFixture } from "ethereum-waffle";
import { deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { CreditTokenStaker as CreditTokenStakerInterface } from "../typechain/CreditTokenStaker";

describe("CreditTokenStaker contract", () => {
    let creditTokenStaker: CreditTokenStakerInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        creditTokenStaker = await CreditTokenStaker(proxyAdmin.address, deployer.address);
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const CreditTokenStaker = await ethers.getContractFactory("CreditTokenStaker", deployer);
        const creditTokenStaker = await CreditTokenStaker.deploy();
        const instance = await creditTokenStaker.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditTokenStaker: _owner cannot be 0x0");
    });

    it("Test #addOwner #addOwners #removeOwner #isOwner", async () => {
        const [deployer, test1Signer, test2Signer] = await ethers.getSigners();

        expect(creditTokenStaker.addOwner(ethers.constants.AddressZero)).to.be.revertedWith("CreditTokenStaker: _newOwner cannot be 0x0");
        expect(creditTokenStaker.removeOwner(ethers.constants.AddressZero)).to.be.revertedWith("CreditTokenStaker: _owner cannot be 0x0");

        await creditTokenStaker.addOwner(test1Signer.address);
        await creditTokenStaker.addOwners([test2Signer.address]);
        await creditTokenStaker.removeOwner(test2Signer.address);

        expect(creditTokenStaker.addOwner(test1Signer.address)).to.be.revertedWith("CreditTokenStaker: _newOwner is already owner");
        expect(creditTokenStaker.removeOwner(test2Signer.address)).to.be.revertedWith("CreditTokenStaker: _owner is not an owner");

        expect(await creditTokenStaker.isOwner(test1Signer.address)).to.be.eq(true);
    });

    it("Test #setCreditToken", async () => {
        const { usdt } = await loadFixture(deployMockTokens);

        expect(creditTokenStaker.setCreditToken(ethers.constants.AddressZero)).to.be.revertedWith("CreditTokenStaker: _creditToken cannot be 0x0");
        await creditTokenStaker.setCreditToken(usdt.address);
        expect(creditTokenStaker.setCreditToken(usdt.address)).to.be.revertedWith("CreditTokenStaker: Cannot run this function twice");
    });

    it("Test #stake/#stakeFor #withdraw/#withdrawFor", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { usdt } = await loadFixture(deployMockTokens);

        await creditTokenStaker.setCreditToken(usdt.address);

        const vaultRewardDistributor = await VaultRewardDistributor(
            proxyAdmin.address,
            creditTokenStaker.address,
            deployer.address,
            usdt.address,
            TOKENS.WETH,
            "MOCK"
        );

        const supplyRewardPool = await BaseReward(proxyAdmin.address, deployer.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "MOCK");
        const borrowedRewardPool = await BaseReward(proxyAdmin.address, deployer.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "MOCK");
        const collateralReward = await CollateralReward(proxyAdmin.address, creditTokenStaker.address, deployer.address, usdt.address, TOKENS.WETH);

        await vaultRewardDistributor.setSupplyRewardPool(supplyRewardPool.address);
        await vaultRewardDistributor.setBorrowedRewardPool(borrowedRewardPool.address);

        const amountIn = ethers.utils.parseUnits("200", 6);

        expect(creditTokenStaker.stake(ethers.constants.AddressZero, amountIn)).to.be.revertedWith("CreditTokenStaker: _vaultRewardDistributor cannot be 0x0");

        await creditTokenStaker.stake(vaultRewardDistributor.address, amountIn);

        expect(await usdt.balanceOf(vaultRewardDistributor.address)).to.be.eql(BigNumber.from(amountIn));

        expect(creditTokenStaker.stakeFor(ethers.constants.AddressZero, deployer.address, amountIn)).to.be.revertedWith(
            "CreditTokenStaker: _collateralReward cannot be 0x0"
        );
        expect(creditTokenStaker.stakeFor(collateralReward.address, ethers.constants.AddressZero, amountIn)).to.be.revertedWith(
            "CreditTokenStaker: _recipient cannot be 0x0"
        );

        await creditTokenStaker.stakeFor(collateralReward.address, deployer.address, amountIn);

        expect(await usdt.balanceOf(collateralReward.address)).to.be.eql(BigNumber.from(amountIn));

        expect(creditTokenStaker.withdraw(ethers.constants.AddressZero, amountIn)).to.be.revertedWith(
            "CreditTokenStaker: _vaultRewardDistributor cannot be 0x0"
        );
        expect(creditTokenStaker.withdrawFor(ethers.constants.AddressZero, deployer.address, amountIn)).to.be.revertedWith(
            "CreditTokenStaker: _collateralReward cannot be 0x0"
        );

        await creditTokenStaker.withdraw(vaultRewardDistributor.address, amountIn);
        await creditTokenStaker.withdrawFor(collateralReward.address, deployer.address, amountIn);
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const newCreditTokenStaker = await creditTokenStaker.connect(wrongSigner);

        expect(newCreditTokenStaker.addOwner(wrongSigner.address)).to.be.revertedWith("CreditTokenStaker: Caller is not an owner");
    });


    // it("Test #stake #withdraw #stakeFor #withdrawFor #setCreditToken", async () => {
    //     const [deployer] = await ethers.getSigners();
    //     const { proxyAdmin } = await loadFixture(deployProxyAdmin);
    //     const { usdt } = await loadFixture(deployMockTokens);

    //     const creditTokenStaker = await CreditTokenStaker(proxyAdmin.address, deployer.address);

    //     await creditTokenStaker.setCreditToken(usdt.address);

    //     const vaultRewardDistributor = await VaultRewardDistributor(
    //         proxyAdmin.address,
    //         creditTokenStaker.address,
    //         deployer.address,
    //         usdt.address,
    //         TOKENS.WETH,
    //         "MOCK"
    //     );

    //     const supplyRewardPool = await BaseReward(proxyAdmin.address, deployer.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "MOCK");
    //     const borrowedRewardPool = await BaseReward(proxyAdmin.address, deployer.address, vaultRewardDistributor.address, usdt.address, TOKENS.WETH, "MOCK");
    //     const collateralReward = await CollateralReward(proxyAdmin.address, deployer.address, deployer.address, usdt.address, TOKENS.WETH);

    //     await vaultRewardDistributor.setSupplyRewardPool(supplyRewardPool.address);
    //     await vaultRewardDistributor.setBorrowedRewardPool(borrowedRewardPool.address);

    //     const amountIn = ethers.utils.parseUnits("200", 6);

    //     await creditTokenStaker.stake(vaultRewardDistributor.address, amountIn.div(2));

    //     expect(await usdt.balanceOf(vaultRewardDistributor.address)).to.be.eql(BigNumber.from(amountIn.div(2)));

    //     await creditTokenStaker.stakeFor(collateralReward.address, deployer.address, amountIn.div(2));

    //     expect(await usdt.balanceOf(collateralReward.address)).to.be.eql(BigNumber.from(amountIn.div(2)));

    //     await vaultRewardDistributor.distribute(0);
    //     await collateralReward.distribute(0);
    // });
});
