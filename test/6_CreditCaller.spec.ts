/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { db, evmMine, increaseDays, increaseMinutes, impersonatedSigner, removeDb, TOKENS, evmSnapshotRun } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as Base } from "../scripts/deploys/1_base";
import { main as Vault } from "../scripts/deploys/2_vault";
import { main as Initialize } from "../scripts/deploys/3_initialize";
import { loadFixture } from "ethereum-waffle";
import { deployAddressProvider, deployMockTokens, deployProxyAdmin } from "./LoadFixture";
import { AbstractVault } from "../typechain";

const ZERO = `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`;
const LIQUIDATE_THRESHOLD = 400;
const MAX_LOAN_DURATION = 365;

async function _swapToken(toToken: string, ethAmountIn: BigNumber) {
    const [deployer] = await ethers.getSigners();
    const gmxRouter = await ethers.getContractAt(require("../scripts/abis/GmxRouter"), "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064", deployer);

    await gmxRouter.swapETHToTokens([TOKENS.WETH, toToken], 0, deployer.address, { value: ethAmountIn });
}

async function mockPriceFeed(tokenFeeds: Array<any>, cb: CallableFunction) {
    const [deployer] = await ethers.getSigners();

    const gmxVaultAddress = `0x489ee077994B6658eAfA855C308275EAd8097C4A`;
    const gmxVault = await ethers.getContractAt(require("../scripts/abis/GmxVault"), gmxVaultAddress, deployer);

    const govSigner = await impersonatedSigner(await gmxVault.gov());

    const MockGmxVaultPriceFeedFactory = await ethers.getContractFactory("MockGmxVaultPriceFeed", deployer);
    const MockGmxVaultPriceFeed = await MockGmxVaultPriceFeedFactory.deploy();
    const mockGmxVaultPriceFeed = await MockGmxVaultPriceFeed.deployed();

    for (const fake of tokenFeeds) {
        await mockGmxVaultPriceFeed.setPrice(fake.token, fake.price);
    }

    return evmSnapshotRun(async () => {
        await gmxVault.connect(govSigner).setPriceFeed(mockGmxVaultPriceFeed.address);
        await evmMine();
        await cb();
    });
}

async function getCollateralReward(recipient: string): Promise<BigNumber> {
    const [deployer] = await ethers.getSigners();
    const collateralReward = await ethers.getContractAt("CollateralReward", db.get("CollateralRewardProxy").logic, deployer);

    return collateralReward.balanceOf(recipient);
}

async function getWethBorrowedRewardVsTokenSupply(vault: AbstractVault): Promise<BigNumber> {
    return vault.balanceOf(await vault.borrowedRewardPool());
}

describe("CreditCaller & CreditManager contract", () => {
    beforeEach(async () => {
        await Base();
        await Vault();
        await Initialize();
    });

    after(async () => {
        removeDb();
    });

    it("Test initialize", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const { addressProvider } = await loadFixture(deployAddressProvider);

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const CreditCaller = await ethers.getContractFactory("CreditCaller", deployer);
        const creditCaller = await CreditCaller.deploy();
        const instance = await creditCaller.deployed();

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [ethers.constants.AddressZero, TOKENS.WETH])
            )
        ).to.be.revertedWith("CreditCaller: _addressProvider cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [addressProvider.address, ethers.constants.AddressZero])
            )
        ).to.be.revertedWith("CreditCaller: _wethAddress cannot be 0x0");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [deployer.address, TOKENS.WETH])
            )
        ).to.be.revertedWith("CreditCaller: _addressProvider is not a contract");

        expect(
            TransparentUpgradeableProxy.deploy(
                instance.address,
                proxyAdmin.address,
                instance.interface.encodeFunctionData("initialize", [addressProvider.address, deployer.address])
            )
        ).to.be.revertedWith("CreditCaller: _wethAddress is not a contract");
    });

    it("Test ETH #openLendCredit #repayCredit #liquidate", async () => {
        const [deployer, illegalSigner] = await ethers.getSigners();
        const { weth } = await loadFixture(deployMockTokens);

        const vault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");

        await vault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await weth.deposit({ value: collateralAmountIn });
        await weth.approve(caller.address, collateralAmountIn);

        const depositer = db.get("GMXDepositorProxy").logic;

        expect(caller.openLendCredit(depositer, ethers.constants.AddressZero, collateralAmountIn, [TOKENS.WETH], [400], deployer.address)).to.be.revertedWith(
            "CreditCaller: _token cannot be 0x0"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, 0, [TOKENS.WETH], [400], deployer.address)).to.be.revertedWith(
            "CreditCaller: _amountIn cannot be 0"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [], deployer.address)).to.be.revertedWith(
            "CreditCaller: _ratios cannot be empty"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [99], deployer.address)).to.be.revertedWith(
            "CreditCaller: MIN_RATIO limit exceeded"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [1001], deployer.address)).to.be.revertedWith(
            "CreditCaller: MAX_RATIO limit exceeded"
        );

        expect(caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [400, 500], deployer.address)).to.be.revertedWith(
            "CreditCaller: Length mismatch"
        );

        expect(
            caller.openLendCredit(depositer, ZERO, collateralAmountIn.mul(2), [TOKENS.WETH], [400], deployer.address, { value: collateralAmountIn })
        ).to.be.revertedWith("CreditCaller: ETH amount mismatch");

        expect(
            caller.openLendCredit(depositer, ZERO, collateralAmountIn, [TOKENS.WETH], [400], illegalSigner.address, { value: collateralAmountIn })
        ).to.be.revertedWith("CreditCaller: Not whitelisted");

        await caller.openLendCredit(depositer, ZERO, collateralAmountIn, [TOKENS.WETH], [400], deployer.address, { value: collateralAmountIn });
        await caller.setAllowlist(ethers.constants.AddressZero);
        await caller.openLendCredit(depositer, TOKENS.WETH, collateralAmountIn, [TOKENS.WETH], [400], deployer.address);

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        expect(creditCounts).to.be.above(BigNumber.from("0"));
        expect(caller.repayCredit(0)).to.be.revertedWith("CreditCaller: Minimum limit exceeded");
        expect(caller.repayCredit(creditCounts.add(1))).to.be.revertedWith("CreditCaller: Index out of range");

        expect(caller.liquidate(deployer.address, 0)).to.be.revertedWith("CreditCaller: Minimum limit exceeded");
        expect(caller.liquidate(deployer.address, creditCounts.add(1))).to.be.revertedWith("CreditCaller: Index out of range");

        const lendCreditInfo = await creditUser.getUserLendCredit(deployer.address, creditCounts);

        expect(lendCreditInfo.amountIn).to.be.eq(BigNumber.from(collateralAmountIn.sub(collateralAmountIn.mul(100).div(1000))));

        const creditRewardTracker = await ethers.getContractAt("CreditRewardTracker", db.get("CreditRewardTrackerProxy").logic, deployer);
        await creditRewardTracker.harvestDepositors();
        await creditRewardTracker.harvestManagers();

        const manager = await ethers.getContractAt("CreditManager", db.get("WETHVaultManagerProxy").logic, deployer);
        await manager.claim(deployer.address);

        await evmSnapshotRun(async () => {
            await increaseMinutes(120);
            await evmMine();
            await manager.claim(deployer.address);
        });

        await manager.balanceOf(deployer.address);
        await manager.pendingRewards(deployer.address);

        expect(manager.borrow(deployer.address, 0)).to.be.revertedWith("CreditManager: Caller is not the caller");
        expect(manager.harvest()).to.be.revertedWith("CreditManager: Caller is not the reward tracker");

        await caller.repayCredit(creditCounts);
    });

    it("Test strategy", async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);
        const collateralAmountIn = ethers.utils.parseEther("1");

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const Depositor = await ethers.getContractFactory("GMXDepositor", deployer);
        const depositor = await Depositor.deploy();
        const instance = await depositor.deployed();

        const data = instance.interface.encodeFunctionData("initialize", [
            db.get("CreditCallerProxy").logic,
            TOKENS.WETH,
            db.get("CreditRewardTrackerProxy").logic,
            deployer.address,
        ]);
        const proxy = await TransparentUpgradeableProxy.deploy(instance.address, proxyAdmin.address, data);

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(
            caller.openLendCredit(proxy.address, ZERO, collateralAmountIn, [TOKENS.WETH], [200], deployer.address, { value: collateralAmountIn })
        ).to.be.revertedWith("CreditCaller: Mismatched strategy");
    });

    it("Test #calcHealth", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await caller.calcHealth(BigNumber.from("100"), BigNumber.from("200"), BigNumber.from("500"));
        await caller.calcHealth(BigNumber.from("200"), BigNumber.from("100"), BigNumber.from("500"));
    });

    it("Test #claimFor", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await caller.claimFor(db.get("CollateralRewardProxy").logic, deployer.address);
    });

    it("Test #setCreditUser", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setCreditUser(ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditUser cannot be 0x0");
        expect(caller.setCreditUser(db.get("CreditUserProxy").logic)).to.be.revertedWith("CreditCaller: Cannot run this function twice");
    });

    it("Test #setCreditTokenStaker", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setCreditTokenStaker(ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditTokenStaker cannot be 0x0");
        expect(caller.setCreditTokenStaker(db.get("CreditTokenStakerProxy").logic)).to.be.revertedWith("CreditCaller: Cannot run this function twice");
    });

    it("Test #addVaultManager", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.addVaultManager(ethers.constants.AddressZero, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith(
            "CreditCaller: _underlyingToken cannot be 0x0"
        );
        expect(caller.addVaultManager(TOKENS.WETH, ethers.constants.AddressZero)).to.be.revertedWith("CreditCaller: _creditManager cannot be 0x0");
        expect(caller.addVaultManager(TOKENS.WETH, db.get("WETHVaultManagerProxy").logic)).to.be.revertedWith("CreditCaller: Not allowed");
    });

    it("Test #addStrategy", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        const depositer = db.get("GMXDepositorProxy").logic;
        const collateralReward = db.get("CollateralRewardProxy").logic;
        const vaults: Array<string> = [];
        const vaultRewards: Array<string> = [];

        expect(caller.addStrategy(ethers.constants.AddressZero, collateralReward, vaults, vaultRewards)).to.be.revertedWith(
            "CreditCaller: _depositor cannot be 0x0"
        );

        expect(caller.addStrategy(depositer, ethers.constants.AddressZero, vaults, vaultRewards)).to.be.revertedWith(
            "CreditCaller: _collateralReward cannot be 0x0"
        );

        vaults.push(db.get("WETHVaultProxy").logic);

        expect(caller.addStrategy(depositer, collateralReward, vaults, vaultRewards)).to.be.revertedWith("CreditCaller: Length mismatch");
    });

    it("Test #setLiquidateThreshold", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setLiquidateThreshold(501)).to.be.revertedWith("CreditCaller: MAX_LIQUIDATE_THRESHOLD limit exceeded");
        expect(caller.setLiquidateThreshold(299)).to.be.revertedWith("CreditCaller: MIN_LIQUIDATE_THRESHOLD limit exceeded");

        await caller.setLiquidateThreshold(LIQUIDATE_THRESHOLD);
    });

    it("Test #setLiquidatorFee", async () => {
        const [deployer] = await ethers.getSigners();

        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.setLiquidatorFee(201)).to.be.revertedWith("CreditCaller: MAX_LIQUIDATOR_FEE limit exceeded");
        expect(caller.setLiquidatorFee(49)).to.be.revertedWith("CreditCaller: MIN_LIQUIDATOR_FEE limit exceeded");

        await caller.setLiquidatorFee(150);
    });

    it("Test MIM #openLendCredit", async () => {
        const [borrower, deployer, liquidityProvider] = await ethers.getSigners();
        // Impersonate one of the MIM minter wallets so we can mint MIM to the borrower user
        const minter = await impersonatedSigner("0xC931f61B1534EB21D8c11B24f3f5Ab2471d4aB50");
        // Fork the MIM contract
        const mim = await ethers.getContractAt(require("../scripts/abis/MIM"), TOKENS.MIM, deployer);

        const vault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        // WETH liquidity supply
        const supplyAmountIn = ethers.utils.parseEther("20");
        // MIM collateral amount
        const collateralAmountIn = ethers.utils.parseEther("0.01");

        // Mint MIM to the borrower
        await mim.connect(minter).mint(borrower.address, ethers.utils.parseEther("1"));

        // Add liquidity to the WETH vault so the borrower can borrow the specified amount
        await vault.connect(liquidityProvider).addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        // Approve the CreditCaller contract to transfer the collateral amount in
        await mim.connect(borrower).approve(caller.address, collateralAmountIn);

        const depositer = db.get("GMXDepositorProxy").logic;

        expect(
            caller.connect(borrower).openLendCredit(
                depositer, // The only depositor in the system
                TOKENS.MIM, // Use MIM as the collateral token
                collateralAmountIn, // Use this as the collateral amount
                [TOKENS.WETH], // Only borrow WETH
                [500], // Take 5X WETH leverage
                borrower.address // The borrower is the recepient of the borrowed amounts
            )
        ).to.be.revertedWith("CreditCaller: The collateral asset must be one of the borrow tokens");
    });

    it("Test repayment & liquidation after 900% increase in ETH price", async () => {
        /* 
            Assuming ETH price increases by over 900%, 
            and we borrow ETH three times, 
            the experimental results should show a health factor below LIQUIDATE_THRESHOLD, with the user having enough GLP only to repay the first loan.
        */

        const [deployer, liquidator] = await ethers.getSigners();

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");
        const wethVault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await wethVault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await caller.openLendCredit(
            db.get("GMXDepositorProxy").logic,
            ZERO,
            collateralAmountIn,
            [TOKENS.WETH, TOKENS.WETH, TOKENS.WETH],
            [500, 300, 100],
            deployer.address,
            {
                value: collateralAmountIn,
            }
        );

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        // Testing a normal liquidation once should theoretically be ineffective.
        await caller.liquidate(deployer.address, creditCounts);

        const aggregator = await ethers.getContractAt("CreditAggregator", db.get("CreditAggregatorProxy").logic, deployer);
        const ethPrice = await aggregator.getTokenPrice(TOKENS.WETH);

        await mockPriceFeed([{ token: TOKENS.WETH, price: ethPrice.mul(100 + 900).div(100) }], async () => {
            const health = await caller.getUserCreditHealth(deployer.address, creditCounts);

            if (health.toNumber() <= LIQUIDATE_THRESHOLD) {
                // If the liquidation robot is not working, an error will occur when the user selects repayment.
                try {
                    await caller.repayCredit(creditCounts);
                } catch (error: any) {
                    expect(error.message).to.match(/CreditCaller: The current position needs to be liquidated/);
                }

                // Re-liquidate the leveraged position placed just now.
                await caller.connect(liquidator).liquidate(deployer.address, creditCounts);
                // The liquidator receives a liquidation fee.
                const { weth } = await loadFixture(deployMockTokens);
                expect(await weth.balanceOf(creditUser.address)).to.be.eq(BigNumber.from(0));
                expect(await weth.balanceOf(liquidator.address)).to.be.above(0);

                expect(await getCollateralReward(deployer.address)).to.be.eq(BigNumber.from(0));
                expect(await getWethBorrowedRewardVsTokenSupply(wethVault as AbstractVault)).to.be.eq(BigNumber.from(0));

                // Attempting to re-liquidate after simulating the liquidation results in an error.
                try {
                    await caller.liquidate(deployer.address, creditCounts);
                } catch (error: any) {
                    expect(error.message).to.match(/CreditCaller: Already terminated/);
                }
            } else {
                await caller.repayCredit(creditCounts);
            }
        });
    });

    it("Test the liquidation situation of different assets for loans", async () => {
        const [deployer] = await ethers.getSigners();

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");
        const wethVault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await wethVault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await _swapToken(TOKENS.USDT, ethers.utils.parseEther("2"));

        const usdtVault = await ethers.getContractAt("ERC20Vault", db.get("USDTVaultProxy").logic, deployer);
        const usdt = await ethers.getContractAt("ERC20", TOKENS.USDT, deployer);
        await usdt.approve(usdtVault.address, ethers.constants.MaxUint256);
        // const dai = await ethers.getContractAt(require("../scripts/abis/DAI"), TOKENS.DAI, deployer);
        // const daiMinter = await impersonatedSigner(`0x10E6593CDda8c58a1d0f14C5164B376352a55f2F`);

        // await dai.connect(daiMinter).mint(deployer.address, supplyAmountIn.mul(10000));
        // await dai.approve(daiVault.address, supplyAmountIn.mul(10000));
        await usdtVault.addLiquidity(await usdt.balanceOf(deployer.address));

        await caller.openLendCredit(db.get("GMXDepositorProxy").logic, ZERO, collateralAmountIn, [TOKENS.WETH, TOKENS.USDT], [200, 100], deployer.address, {
            value: collateralAmountIn,
        });

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        const aggregator = await ethers.getContractAt("CreditAggregator", db.get("CreditAggregatorProxy").logic, deployer);
        const ethPrice = await aggregator.getTokenPrice(TOKENS.WETH);
        const usdtPrice = await aggregator.getTokenPrice(TOKENS.USDT);

        await mockPriceFeed(
            [
                { token: TOKENS.WETH, price: ethPrice.mul(100 + 900).div(100) },
                { token: TOKENS.USDT, price: usdtPrice },
            ],
            async () => {
                const health = await caller.getUserCreditHealth(deployer.address, creditCounts);

                if (health.toNumber() <= LIQUIDATE_THRESHOLD) {
                    await caller.liquidate(deployer.address, creditCounts);
                }
            }
        );

        // Just now was a snapshot, now it's normal repayment.
        await caller.repayCredit(creditCounts);
    });

    it("Test simulate liquidation after normal timeout, with no significant change in GLP price", async () => {
        const [deployer] = await ethers.getSigners();

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");
        const wethVault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await wethVault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await caller.openLendCredit(
            db.get("GMXDepositorProxy").logic,
            ZERO,
            collateralAmountIn,
            [TOKENS.WETH, TOKENS.WETH, TOKENS.WETH],
            [500, 300, 100],
            deployer.address,
            {
                value: collateralAmountIn,
            }
        );

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        await evmSnapshotRun(async () => {
            await increaseDays(MAX_LOAN_DURATION);
            await evmMine();

            // Simulating repayment after MAX_LOAN_DURATION days without payment will result in an error if repayment is attempted at this time.
            try {
                await caller.repayCredit(creditCounts);
            } catch (error: any) {
                expect(error.message).to.match(/CreditCaller: Already timeout/);
            }

            await caller.liquidate(deployer.address, creditCounts);

            // After simulating the liquidation, an error will occur if the user continues to repay the loan.
            try {
                await caller.repayCredit(creditCounts);
            } catch (error: any) {
                expect(error.message).to.match(/CreditCaller: Already terminated/);
            }
        });
    });

    it("Test after simulating repayment or liquidation, the user will be unable to continue borrowing", async () => {
        const [deployer] = await ethers.getSigners();

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");
        const wethVault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await wethVault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await caller.openLendCredit(
            db.get("GMXDepositorProxy").logic,
            ZERO,
            collateralAmountIn,
            [TOKENS.WETH, TOKENS.WETH, TOKENS.WETH],
            [500, 300, 100],
            deployer.address,
            {
                value: collateralAmountIn,
            }
        );

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        await caller.repayCredit(creditCounts);

        try {
            await caller.openLendCredit(
                db.get("GMXDepositorProxy").logic,
                ZERO,
                collateralAmountIn,
                [TOKENS.WETH, TOKENS.WETH, TOKENS.WETH],
                [500, 300, 100],
                deployer.address,
                {
                    value: collateralAmountIn,
                }
            );
        } catch (error: any) {
            expect(error.message).to.match(/CreditCaller: The next loan period is invalid/);
        }
    });

    it("Test repayment & liquidation after 99% drops in ETH price", async () => {
        const [deployer] = await ethers.getSigners();

        const supplyAmountIn = ethers.utils.parseEther("20");
        const collateralAmountIn = ethers.utils.parseEther("1");
        const wethVault = await ethers.getContractAt("ETHVault", db.get("WETHVaultProxy").logic, deployer);
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        await wethVault.addLiquidity(supplyAmountIn, { value: supplyAmountIn });

        await caller.openLendCredit(
            db.get("GMXDepositorProxy").logic,
            ZERO,
            collateralAmountIn,
            [TOKENS.WETH, TOKENS.WETH, TOKENS.WETH],
            [500, 300, 100],
            deployer.address,
            {
                value: collateralAmountIn,
            }
        );

        const creditUser = await ethers.getContractAt("CreditUser", db.get("CreditUserProxy").logic, deployer);
        const creditCounts = await creditUser.getUserCounts(deployer.address);

        const aggregator = await ethers.getContractAt("CreditAggregator", db.get("CreditAggregatorProxy").logic, deployer);
        const ethPrice = await aggregator.getTokenPrice(TOKENS.WETH);

        await mockPriceFeed([{ token: TOKENS.WETH, price: ethPrice.mul(100 - 99).div(100) }], async () => {
            const health = await caller.getUserCreditHealth(deployer.address, creditCounts);

            expect(health.toNumber()).to.be.above(LIQUIDATE_THRESHOLD);

            await caller.repayCredit(creditCounts);

            const { weth } = await loadFixture(deployMockTokens);
            expect(await weth.balanceOf(creditUser.address)).to.be.eq(BigNumber.from(0));

            expect(await getCollateralReward(deployer.address)).to.be.eq(BigNumber.from(0));
            expect(await getWethBorrowedRewardVsTokenSupply(wethVault as AbstractVault)).to.be.eq(BigNumber.from(0));
        });
    });

    it("Test #renounceOwnership", async () => {
        const [deployer] = await ethers.getSigners();
        const caller = await ethers.getContractAt("CreditCaller", db.get("CreditCallerProxy").logic, deployer);

        expect(caller.renounceOwnership()).to.be.revertedWith("CreditCaller: Not allowed");
    });
});
