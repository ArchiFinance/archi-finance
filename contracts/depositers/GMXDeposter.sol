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
import { IDeposter } from "./interfaces/IDeposter.sol";
import { IDepositerRewardDistributor } from "../rewards/interfaces/IDepositerRewardDistributor.sol";

contract GMXDeposter is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IDeposter {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant FEE_DENOMINATOR = 100;
    uint256 private constant MAX_PLATFORM_FEE = 15;

    address public wethAddress;
    address public caller;
    address public executer;
    address public distributer;
    address public platform;
    uint256 public platformFee;

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

    function initialize(
        address _caller,
        address _wethAddress,
        address _platform
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        caller = _caller;
        wethAddress = _wethAddress;
        platform = _platform;
        platformFee = 10;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function mint(address _token, uint256 _amountIn) public payable override onlyCaller returns (address, uint256) {
        _harvest();

        if (_token == ZERO) {
            _wrapETH(_amountIn);

            _token = wethAddress;
        } else {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;
        }

        _approve(_token, executer, _amountIn);

        (address mintedToken, uint256 amountOut) = IGMXExecuter(executer).mint(_token, _amountIn);

        emit Mint(_token, _amountIn, amountOut);

        return (mintedToken, amountOut);
    }

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) public payable override onlyCaller returns (uint256) {
        _harvest();

        uint256 amountOut = IGMXExecuter(executer).withdraw(_tokenOut, _amountIn, _minOut);

        IERC20Upgradeable(_tokenOut).safeTransfer(msg.sender, amountOut);

        emit Withdraw(_tokenOut, _amountIn, amountOut);

        return amountOut;
    }

    function _harvest() internal returns (uint256) {
        uint256 rewards;

        rewards = IGMXExecuter(executer).claimRewards();

        if (platform != address(0)) {
            uint256 fees = rewards.mul(platformFee).div(FEE_DENOMINATOR);

            IERC20Upgradeable(wethAddress).safeTransfer(platform, fees);

            rewards = rewards.sub(fees);
        }

        if (rewards > 0) {
            ClaimedReward storage claimedReward = claimedRewards[wethAddress];
            claimedReward.rewards = claimedReward.rewards.add(rewards);

            _approve(wethAddress, distributer, rewards);

            IDepositerRewardDistributor(distributer).distribute(rewards);

            emit Harvest(rewards);
        }

        return rewards;
    }

    function harvest() public nonReentrant returns (uint256) {
        return _harvest();
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

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= MAX_PLATFORM_FEE, "GMXDeposter: Maximum limit exceeded");

        platformFee = _platformFee;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _wrapETH(uint256 _amountIn) internal {
        require(msg.value == _amountIn, "GMXDeposter: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }
}
