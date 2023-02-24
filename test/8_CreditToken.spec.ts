/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { CreditToken as CreditTokenInterface } from "../typechain/CreditToken";
import { removeDb } from "../scripts/utils";

describe("CreditToken contract", () => {
    const amountIn = ethers.utils.parseEther("100");
    let creditToken: CreditTokenInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();

        const fsGLP = `0x1addd80e6039594ee970e5872d247bf0414c8903`;

        const CreditToken = await ethers.getContractFactory("CreditToken", deployer);
        creditToken = await (await CreditToken.deploy(deployer.address, fsGLP)).deployed();
    });

    after(async () => {
        removeDb();
    });

    it("Test #mint", async () => {
        const [deployer] = await ethers.getSigners();

        await creditToken.mint(deployer.address, amountIn);
    });

    it("Test #burn", async () => {
        const [deployer] = await ethers.getSigners();

        await creditToken.mint(deployer.address, amountIn);
        await creditToken.burn(deployer.address, amountIn);
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const newCreditToken = await creditToken.connect(wrongSigner);

        expect(newCreditToken.mint(deployer.address, amountIn)).to.be.revertedWith("CreditToken: Caller is not the operator");
    });
});
