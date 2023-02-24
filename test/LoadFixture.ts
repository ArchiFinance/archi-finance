/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { TOKENS, waitTx } from "../scripts/utils";
import { main as ProxyAdmin } from "../scripts/modules/ProxyAdmin";
import { main as AddressProvider } from "../scripts/modules/AddressProvider";

async function deployProxyAdmin() {
    const proxyAdmin = await ProxyAdmin();

    return { proxyAdmin };
}

async function deployMockUsers() {
    const platform = new ethers.Wallet(ethers.Wallet.createRandom(), ethers.getDefaultProvider());
    const mocker = new ethers.Wallet(ethers.Wallet.createRandom(), ethers.getDefaultProvider());

    return { platform, mocker };
}

async function deployMockTokens() {
    const [deployer] = await ethers.getSigners();

    const MockUSDT = await ethers.getContractFactory("MockToken", deployer);
    const mockUSDT = await MockUSDT.deploy("Tether USD", "USDT", 6);
    const usdt = await mockUSDT.deployed();

    const weth = await ethers.getContractAt("WETH9", TOKENS.WETH);
    const fsGLP = await ethers.getContractAt("IERC20", `0x1aDDD80E6039594eE970E5872D247bf0414C8903`);

    return { usdt, weth, fsGLP };
}

async function deployAddressProvider() {
    const addressProvider = await AddressProvider();

    await waitTx([await addressProvider.setGmxRewardRouter(`0xB95DB5B167D75e6d04227CfFFA61069348d271F5`)]);
    await waitTx([await addressProvider.setGmxRewardRouterV1(`0xa906f338cb21815cbc4bc87ace9e68c87ef8d8f1`)]);

    return { addressProvider };
}

export { deployProxyAdmin, deployMockUsers, deployMockTokens, deployAddressProvider };
