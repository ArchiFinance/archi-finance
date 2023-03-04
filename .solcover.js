module.exports = {
    client: require('ganache-cli'),
    skipFiles: ["./mocks", "./interfaces", "./libraries", "./Timelock.sol", "./PlatformTreasury.sol"],
    modifierWhitelist: ["initializer", "nonReentrant"],
    mocha: {
        enableTimeouts: false,
    },
};