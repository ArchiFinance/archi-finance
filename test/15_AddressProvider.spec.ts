/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { AddressProvider as AddressProviderInterface } from "../typechain/AddressProvider";
import { removeDb } from "../scripts/utils";

describe("AddressProvider contract", () => {
    let addressProvider: AddressProviderInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();

        const AddressProvider = await ethers.getContractFactory("AddressProvider", deployer);
        const instance = await AddressProvider.deploy();

        addressProvider = await instance.deployed();
    });

    after(async () => {
        removeDb();
    });

    it("Test #getGmxRewardRouter", async () => {
        expect(addressProvider.setGmxRewardRouter(ethers.constants.AddressZero)).to.be.revertedWith("AddressProvider: _v cannot be 0x0");

        await addressProvider.setGmxRewardRouter("0xB95DB5B167D75e6d04227CfFFA61069348d271F5");
        await addressProvider.getGmxRewardRouter();
    });

    it("Test #getGmxRewardRouterV1", async () => {
        expect(addressProvider.setGmxRewardRouterV1(ethers.constants.AddressZero)).to.be.revertedWith("AddressProvider: _v cannot be 0x0");

        await addressProvider.setGmxRewardRouterV1("0xa906f338cb21815cbc4bc87ace9e68c87ef8d8f1");
        await addressProvider.getGmxRewardRouterV1();
    });

    it("Test #getCreditAggregator", async () => {
        const [deployer] = await ethers.getSigners();
        expect(addressProvider.setCreditAggregator(ethers.constants.AddressZero)).to.be.revertedWith("AddressProvider: _v cannot be 0x0");

        await addressProvider.setCreditAggregator(deployer.address);
        await addressProvider.getCreditAggregator();
    });

    it("Test #_getAddress", async () => {
        expect(addressProvider.getCreditAggregator()).to.be.revertedWith("AddressProvider: Address not found");
    });

    it("Test #renounceOwnership", async () => {
        expect(addressProvider.renounceOwnership()).to.be.revertedWith("AddressProvider: Not allowed");
    });
});
