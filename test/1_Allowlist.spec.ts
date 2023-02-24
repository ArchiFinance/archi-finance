/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { main as Allowlist } from "../scripts/modules/Allowlist";
import { Allowlist as AllowlistInterface } from "../typechain/Allowlist";
import { removeDb } from "../scripts/utils";

describe("Allowlist contract", () => {
    let allowList: AllowlistInterface;

    beforeEach(async () => {
        allowList = await Allowlist();
    });

    after(async () => {
        removeDb();
    });

    it("Test #permit #forbid #togglePassed #can", async () => {
        const [deployer] = await ethers.getSigners();

        expect(allowList.permit([ethers.constants.AddressZero])).to.be.revertedWith("Allowlist: Account cannot be 0x0");

        expect(await allowList.can(deployer.address)).to.be.eq(false);

        await allowList.permit([deployer.address]);

        expect(await allowList.can(deployer.address)).to.be.eq(true);

        await allowList.forbid([deployer.address]);

        expect(await allowList.can(deployer.address)).to.be.eq(false);

        await allowList.togglePassed();

        expect(await allowList.can(deployer.address)).to.be.eq(true);
    });

    it("Test #renounceOwnership", async () => {
        expect(allowList.renounceOwnership()).to.be.revertedWith("Allowlist: Not allowed");
    });
});
