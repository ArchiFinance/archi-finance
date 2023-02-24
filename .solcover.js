module.exports = {
    client: require('ganache-cli'),
    skipFiles: ["./mocks", "./interfaces", "./libraries", "./Timelock.sol", "./PlatformTreasury.sol"],
    mocha: {
        enableTimeouts: false,
    },
};