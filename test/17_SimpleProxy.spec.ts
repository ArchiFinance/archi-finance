/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { SimpleProxy as SimpleProxyInterface } from "../typechain/SimpleProxy";
import { removeDb } from "../scripts/utils";

describe("SimpleProxy contract", () => {
    let simpleProxy: SimpleProxyInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();

        const SimpleProxy = await ethers.getContractFactory("SimpleProxy", deployer);
        simpleProxy = await (await SimpleProxy.deploy(deployer.address)).deployed();
    });

    after(async () => {
        removeDb();
    });

    it("Test #setPendingOwner #acceptOwner #execute", async () => {
        const [deployer, test1Signer] = await ethers.getSigners();

        const MockToken = await ethers.getContractFactory("MockToken", deployer);
        const mockToken = await (await MockToken.deploy("Mock token", "MT", 18)).deployed();

        expect(
            simpleProxy.execute(mockToken.address, mockToken.interface.encodeFunctionData("burn", [simpleProxy.address, ethers.utils.parseEther("100")]))
        ).to.be.revertedWith("Failed");

        await simpleProxy.execute(mockToken.address, mockToken.interface.encodeFunctionData("mint", [simpleProxy.address, ethers.utils.parseEther("100")]));
        await simpleProxy.execute(mockToken.address, mockToken.interface.encodeFunctionData("decimals"));

        expect(await mockToken.balanceOf(simpleProxy.address)).to.be.eq(BigNumber.from(ethers.utils.parseEther("100")));

        await simpleProxy.setPendingOwner(test1Signer.address);
        await simpleProxy.acceptOwner();
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const newSimpleProxy = await simpleProxy.connect(wrongSigner);

        expect(newSimpleProxy.setPendingOwner(wrongSigner.address)).to.be.revertedWith("NotAuthorized()");
    });
});
