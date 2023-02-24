/* eslint-disable node/no-missing-import */
import { ethers } from "hardhat";
import { expect } from "chai";
import { removeDb, TOKENS } from "../scripts/utils";
import { BigNumber } from "ethers";
import { main as CreditUser } from "../scripts/modules/CreditUser";
import { CreditUser as CreditUserInterface } from "../typechain/CreditUser";
import { deployProxyAdmin } from "./LoadFixture";
import { loadFixture } from "ethereum-waffle";

describe("CreditUser contract", () => {
    let creditUser: CreditUserInterface;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const { proxyAdmin } = await loadFixture(deployProxyAdmin);

        creditUser = await CreditUser(proxyAdmin.address, deployer.address);
    });

    after(async () => {
        removeDb();
    });

    it("Test #lendCreditIndex #getLendCreditsUsers #getUserCounts", async () => {
        const [deployer] = await ethers.getSigners();

        expect(creditUser.accrueSnapshot(ethers.constants.AddressZero)).to.be.revertedWith("CreditUser: _recipient cannot be 0x0");

        await creditUser.accrueSnapshot(deployer.address);

        expect(await creditUser.lendCreditIndex()).to.be.equal(1);
        expect(await creditUser.getLendCreditUsers(1)).to.be.equal(deployer.address);
        expect(await creditUser.getUserCounts(deployer.address)).to.be.equal(1);
    });

    it("Test #createUserLendCredit", async () => {
        const [deployer] = await ethers.getSigners();

        const GMXDepositor = await ethers.getContractFactory("GMXDepositor");
        const gmxDepositor = await GMXDepositor.deploy();

        const CreditManager = await ethers.getContractFactory("CreditManager");
        const creditManager = await CreditManager.deploy();

        await creditUser.accrueSnapshot(deployer.address);

        const amountIn = ethers.utils.parseEther("123");

        const userLendCreditParams = {
            recipient: deployer.address,
            borrowedIndex: 1,
            depositor: gmxDepositor.address,
            token: TOKENS.WETH,
            amountIn: amountIn,
            borrowedTokens: [TOKENS.USDT, TOKENS.USDC],
            ratios: [400, 500],
        };

        await creditUser.createUserLendCredit(
            userLendCreditParams.recipient,
            userLendCreditParams.borrowedIndex,
            userLendCreditParams.depositor,
            userLendCreditParams.token,
            userLendCreditParams.amountIn,
            userLendCreditParams.borrowedTokens,
            userLendCreditParams.ratios
        );

        const userBorrowedParams = {
            recipient: deployer.address,
            borrowedIndex: 1,
            creditManagers: [creditManager.address],
            borrowedAmountOuts: [amountIn],
            collateralMintedAmount: amountIn,
            borrowedMintedAmount: [amountIn],
        };

        await creditUser.createUserBorrowed(
            userBorrowedParams.recipient,
            userBorrowedParams.borrowedIndex,
            userBorrowedParams.creditManagers,
            userBorrowedParams.borrowedAmountOuts,
            userBorrowedParams.collateralMintedAmount,
            userBorrowedParams.borrowedMintedAmount
        );

        const borrowedIndex = await creditUser.getUserCounts(deployer.address);
        const userLendCredit = await creditUser.getUserLendCredit(deployer.address, borrowedIndex);

        expect(userLendCredit.depositor).to.be.equal(gmxDepositor.address);
        expect(userLendCredit.token).to.be.equal(TOKENS.WETH);
        expect(userLendCredit.amountIn).to.be.equal(userLendCreditParams.amountIn);
        expect(userLendCredit.borrowedTokens).to.be.eql(userLendCreditParams.borrowedTokens);
        expect(userLendCredit.ratios).to.be.eql([BigNumber.from("400"), BigNumber.from("500")]);

        const userBorrowed = await creditUser.getUserBorrowed(deployer.address, borrowedIndex);

        expect(userBorrowed.creditManagers).to.be.eql([creditManager.address]);
        expect(userBorrowed.borrowedAmountOuts).to.be.eql(userBorrowedParams.borrowedAmountOuts);
        expect(userBorrowed.collateralMintedAmount).to.be.eql(userBorrowedParams.collateralMintedAmount);
        expect(userBorrowed.borrowedMintedAmount).to.be.eql(userBorrowedParams.borrowedMintedAmount);
        expect(userBorrowed.mintedAmount).to.be.equal(ethers.utils.parseEther("246"));

        await creditUser.isTerminated(deployer.address, borrowedIndex);
        await creditUser.isTimeout(deployer.address, borrowedIndex, BigNumber.from(60 * 60));
        await creditUser.destroy(deployer.address, borrowedIndex);
    });

    it("Test modifiers", async () => {
        const [deployer, wrongSigner] = await ethers.getSigners();

        const newCreditUser = await creditUser.connect(wrongSigner);

        expect(newCreditUser.accrueSnapshot(deployer.address)).to.be.revertedWith("CreditUser: Caller is not the caller");
    });
});
