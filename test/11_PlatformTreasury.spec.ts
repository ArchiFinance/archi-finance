/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { main as PlatformTreasury } from "../scripts/modules/PlatformTreasury";
import { main as SimpleProxy } from "../scripts/modules/SimpleProxy";
import { loadFixture } from "ethereum-waffle";
import { deployMockTokens, deployMockUsers } from "./LoadFixture";
import { BigNumber } from "ethers";
import { removeDb } from "../scripts/utils";

describe("PlatformTreasury contract", () => {
    after(async () => {
        removeDb();
    });

    it("#setOperator #withdrawTo #execute", async () => {
        const [deployer] = await ethers.getSigners();
        const { mocker } = await loadFixture(deployMockUsers);
        const { usdt } = await loadFixture(deployMockTokens);

        const platformTreasury = await PlatformTreasury(deployer.address);
        const simpleProxy = await SimpleProxy(platformTreasury.address);

        const mintedAmount = ethers.utils.parseUnits("100", 6);

        await usdt.mint(platformTreasury.address, mintedAmount);

        expect(await usdt.balanceOf(platformTreasury.address)).to.be.eql(BigNumber.from(mintedAmount));

        await platformTreasury.withdrawTo(usdt.address, mintedAmount, mocker.address);

        expect(await usdt.balanceOf(mocker.address)).to.be.eql(BigNumber.from(mintedAmount));
        expect(await usdt.balanceOf(platformTreasury.address)).to.be.eql(BigNumber.from("0"));

        await platformTreasury.execute(
            simpleProxy.address,
            simpleProxy.interface.encodeFunctionData("execute", [usdt.address, usdt.interface.encodeFunctionData("mint", [mocker.address, mintedAmount])])
        );

        expect(await usdt.balanceOf(mocker.address)).to.be.eql(BigNumber.from(mintedAmount.mul(2)));

        await platformTreasury.setOperator(mocker.address);

        expect(await platformTreasury.operator()).to.be.eql(mocker.address);
    });
});
