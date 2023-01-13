// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IWETH } from "../interfaces/IWETH.sol";
import { IGMXExecuter } from "./interfaces/IGMXExecuter.sol";
import { IDepositerRewardDistributor } from "../rewards/interfaces/IDepositerRewardDistributor.sol";

contract GMXDeposter is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint256 private constant FEE_DENOMINATOR = 100;
    uint256 private constant MAX_PLATFORM_FEE = 10;

    address public caller;
    address public executer;
    address public distributer;
    address public platform;

    struct ClaimedReward {
        uint256 rewards;
    }

    mapping(address => ClaimedReward) public claimedRewards;

    modifier onlyCaller() {
        require(caller == msg.sender, "GMXDeposter: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _caller, address _platform) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        caller = _caller;
        platform = _platform;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function mint(address _token, uint256 _amountIn) public payable onlyCaller returns (address, uint256) {
        if (_isETH(_token)) {
            IWETH(WETH).deposit{ value: _amountIn }();

            _token = WETH;
        } else {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;
        }

        _approve(_token, executer, _amountIn);

        (address mintedToken, uint256 amountOut) = IGMXExecuter(executer).mint(_token, _amountIn);

        return (mintedToken, amountOut);
    }

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) public payable onlyCaller returns (uint256) {
        uint256 amountOut = IGMXExecuter(executer).withdraw(_tokenOut, _amountIn, _minOut);

        IERC20Upgradeable(_tokenOut).safeTransfer(msg.sender, amountOut);

        return amountOut;
    }

    function claimRewards() external nonReentrant returns (uint256) {
        uint256 rewards;

        rewards = IGMXExecuter(executer).claimRewards();

        if (platform != address(0)) {
            uint256 fees = rewards.mul(MAX_PLATFORM_FEE).div(FEE_DENOMINATOR);

            IERC20Upgradeable(WETH).safeTransfer(platform, fees);

            rewards = rewards.sub(fees);
        }

        ClaimedReward storage claimedReward = claimedRewards[WETH];
        claimedReward.rewards = claimedReward.rewards.add(rewards);

        _approve(WETH, distributer, rewards);

        IDepositerRewardDistributor(distributer).distribute(rewards);

        return rewards;
    }

    function setExecuter(address _executer) external onlyOwner {
        require(executer == address(0), "GMXDeposter: Cannot run this function twice");
        executer = _executer;
    }

    function setDistributer(address _distributer) external onlyOwner {
        require(distributer == address(0), "GMXDeposter: Cannot run this function twice");
        distributer = _distributer;
    }

    function setPlatform(address _platform) external onlyOwner {
        platform = _platform;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _isETH(address _token) internal pure returns (bool) {
        return _token == ZERO;
    }
}
