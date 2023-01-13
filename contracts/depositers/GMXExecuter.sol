// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IGMXExecuter } from "./interfaces/IGMXExecuter.sol";
import { IGmxRewardRouter } from "./interfaces/IGmxRewardRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { IAddressProvider } from "../interfaces/IAddressProvider.sol";

contract GMXExecuter is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IGMXExecuter {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public addressProvider;
    address public deposter;

    modifier onlyDeposter() {
        require(deposter == msg.sender, "GMXExecuter: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _addressProvider, address _deposter) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        addressProvider = _addressProvider;
        deposter = _deposter;

        _transferOwnership(_deposter);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function mint(address _token, uint256 _amountIn) external payable override nonReentrant onlyDeposter returns (address, uint256) {
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);

        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        _approve(_token, IGmxRewardRouter(router).glpManager(), _amountIn);

        uint256 amountOut = IGmxRewardRouter(router).mintAndStakeGlp(_token, _amountIn, 0, 0);

        return (IGmxRewardRouter(router).stakedGlpTracker(), amountOut);
    }

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) public override onlyDeposter returns (uint256) {
        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        return IGmxRewardRouter(router).unstakeAndRedeemGlp(_tokenOut, _amountIn, _minOut, deposter);
    }

    function claimRewards() external override nonReentrant onlyDeposter returns (uint256) {
        bool shouldClaimGmx = true;
        bool shouldStakeGmx = false;
        bool shouldClaimEsGmx = true;
        bool shouldStakeEsGmx = false;
        bool shouldStakeMultiplierPoints = false;
        bool shouldClaimWeth = true;
        bool shouldConvertWethToEth = false;

        uint256 before = IERC20Upgradeable(WETH).balanceOf(address(this));

        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        IGmxRewardRouter(router).handleRewards(
            shouldClaimGmx,
            shouldStakeGmx,
            shouldClaimEsGmx,
            shouldStakeEsGmx,
            shouldStakeMultiplierPoints,
            shouldClaimWeth,
            shouldConvertWethToEth
        );

        uint256 rewards = IERC20Upgradeable(WETH).balanceOf(address(this)) - before;

        IERC20Upgradeable(WETH).safeTransfer(deposter, rewards);

        return rewards;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        if (IERC20Upgradeable(_token).allowance(address(this), _spender) < _amount) {
            IERC20Upgradeable(_token).safeApprove(_spender, MAX_INT);
        }
    }
}
