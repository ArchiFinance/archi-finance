/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as CollateralReward } from "../scripts/modules/CollateralReward";
import { loadFixture } from "ethereum-waffle";
import { deployMockTokens, deployProxyAdmin } from "./LoadFixture";

describe("CollateralReward contract", () => {
    beforeEach(async () => {
        //
    });

    after(async () => {
        removeDb();
    });

    it("Test ##withdraw #withdrawFor", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { usdt } = await loadFixture(deployMockTokens);

        const collateralReward = await CollateralReward(proxyAdmin.address, deployer.address, deployer.address, usdt.address, TOKENS.WETH);
        const mintedAmount = ethers.utils.parseUnits("100", 6);

        await usdt.mint(deployer.address, mintedAmount);
        await usdt.approve(collateralReward.address, ethers.constants.MaxUint256);
        await collateralReward.stakeFor(deployer.address, mintedAmount);

        expect(collateralReward.withdrawFor(deployer.address, mintedAmount.mul(2))).to.be.revertedWith("CollateralReward: Insufficient amounts");
        expect(collateralReward.withdraw(mintedAmount.div(2))).to.be.revertedWith("CollateralReward: Not allowed");

        expect(await collateralReward.balanceOf(deployer.address)).to.be.eql(BigNumber.from(mintedAmount));

        await collateralReward.withdrawFor(deployer.address, mintedAmount);
    });
});
