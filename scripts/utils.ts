import { ethers, network } from "hardhat";
import { Contract, ContractTransaction, PayableOverrides } from "ethers";
import JSONdb from "simple-json-db";
import { BytesLike, Interface } from "ethers/lib/utils";
import { SimpleProxy as SimpleProxyInterface } from "../typechain";

const fs = require("fs");
const path = require("path");
const dbName = `deployed-${network.name}.json`;
const db = new JSONdb(dbName);

/* eslint-disable */
const readJSON = (filePath: string): any => {
    return JSON.parse(
        fs.readFileSync(filePath, {
            encoding: "utf8",
        })
    );
};

/* eslint-disable */
const writeJSON = (data: any, filePath: string) => {
    fs.mkdirSync(path.dirname(filePath), {
        recursive: true,
    });

    fs.writeFileSync(filePath, JSON.stringify(data));
};

const removeDb = () => {
    try {
        fs.unlinkSync(dbName);
    } catch (err) {
    }
}

const waitTx = async (f: Array<ContractTransaction>, confirmations?: number, silence?: boolean) => {
    for (let i = 0; i < f.length; i++) {
        const receipt = f[i];

        await receipt.wait(confirmations);
    }
}

const encoder = (types: any, values: any) => {
    const abiCoder = ethers.utils.defaultAbiCoder;
    const encodedParams = abiCoder.encode(types, values);
    return encodedParams.slice(2);
};

const create2Address = (factoryAddress: any, saltHex: any, initCode: any) => {
    const create2Addr = ethers.utils.getCreate2Address(factoryAddress, saltHex, ethers.utils.keccak256(initCode));
    return create2Addr;
};

const TOKENS: {
    [key: string]: string;
} = {
    WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    USDT: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
    USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
    WBTC: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
    DAI: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
    LINK: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
    UNI: "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0",
    FRAX: "0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F",
}

const TOKENS_DECIMALS: {
    [key: string]: number;
} = {
    WETH: 18,
    USDT: 6,
    USDC: 6,
    WBTC: 8,
    DAI: 18,
    LINK: 18,
    UNI: 18,
    FRAX: 18,
}

interface IMulticall {
    // multicall(f: any): any;
    multicall(
        data: BytesLike[],
        overrides?: PayableOverrides & { from?: string | Promise<string> }
    ): Promise<ContractTransaction>;
    interface: Interface;
}

class MulticallTxs {
    confirmations: number;
    instance: IMulticall;
    txs: any = [];

    constructor(instance: IMulticall, _confirmations?: number) {
        this.instance = instance;
        this.confirmations = _confirmations || 1;
    }

    add(f: any) {
        this.txs.push(f);

        return this;
    }

    addEncodeFunctionData(functionFragment: string, values?: ReadonlyArray<any>) {
        this.add(this.instance.interface.encodeFunctionData(functionFragment, values));

        return this;
    }

    async waitTx() {
        const txs = this.txs;

        this.txs = [];

        return waitTx([await this.instance.multicall(txs)], this.confirmations);
    }
}

class CallTxs {
    confirmations: number;

    constructor(_confirmations?: number) {
        this.confirmations = _confirmations || 1;
    }

    async waitTx(f: Array<ContractTransaction>) {
        return waitTx(f, this.confirmations);
    }
}

class SimpleProxyCall {
    simpleProxy: SimpleProxyInterface;
    address: string;

    constructor(simpleProxy: SimpleProxyInterface) {
        this.simpleProxy = simpleProxy;
        this.address = simpleProxy.address;
    }

    async execute(instance: Contract, functionFragment: string, values: ReadonlyArray<any>, overrides?: PayableOverrides & { from?: string | Promise<string> }) {
        return this.simpleProxy.execute(instance.address, instance.interface.encodeFunctionData(functionFragment, []), overrides);
    }
}

const sleep = async (time: number) => {
    return new Promise(function (resolve) {
        setTimeout(resolve, time);
    });
}

const increaseDays = async (days?: number) => {
    days = days || 1;

    return network.provider.request({
        method: "evm_increaseTime",
        params: [60 * 60 * 24 * days],
    });
}

const increaseMinutes = async (minutes?: number) => {
    minutes = minutes || 1;

    return network.provider.request({
        method: "evm_increaseTime",
        params: [60 * minutes],
    });
}

const evmMine = async () => {
    return network.provider.request({
        method: "evm_mine",
        params: [],
    });
}

const evmRevert = async (snapshotId: string) => {
    return network.provider.request({
        method: "evm_revert",
        params: [snapshotId],
    });
}

const evmSnapshot = async () => {
    return network.provider.request({
        method: "evm_snapshot",
        params: [],
    });
}

const hardHatReset = async () => {
    return network.provider.request({
        method: "hardhat_reset",
        params: [],
    });
}

export {
    db,
    readJSON,
    writeJSON,
    removeDb,
    waitTx,
    encoder,
    create2Address,
    TOKENS,
    TOKENS_DECIMALS,
    MulticallTxs,
    CallTxs,
    SimpleProxyCall,
    sleep,
    increaseDays,
    increaseMinutes,
    evmMine,
    evmRevert,
    evmSnapshot,
    hardHatReset
}