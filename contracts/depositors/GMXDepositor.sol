// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { IWETH } from "../interfaces/IWETH.sol";
import { IGMXExecutor } from "./interfaces/IGMXExecutor.sol";
import { IDepositor } from "./interfaces/IDepositor.sol";
import { IDepositorRewardDistributor } from "../rewards/interfaces/IDepositorRewardDistributor.sol";

/* 
The GMXDepositor contract is mainly used to bind the relationship between CreditCaller and Executor. 
However, when a user needs to withdraw or invest, 
it will send data to Executor to execute.
*/

contract GMXDepositor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IDepositor {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant FEE_DENOMINATOR = 100;
    uint256 private constant MAX_PLATFORM_FEE = 15;

    address public wethAddress;
    address public caller;
    address public executor;
    address public distributer;
    address public rewardTracker;
    address public platform;
    uint256 public platformFee;

    struct ClaimedReward {
        uint256 rewards;
    }

    mapping(address => ClaimedReward) public claimedRewards;

    modifier onlyCaller() {
        require(caller == msg.sender, "GMXDepositor: Caller is not the caller");
        _;
    }

    modifier onlyRewardTracker() {
        require(rewardTracker == msg.sender, "GMXDepositor: Caller is not the reward tracker");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(
        address _caller,
        address _wethAddress,
        address _rewardTracker,
        address _platform
    ) external initializer {
        require(_caller != address(0), "GMXDepositor: _caller cannot be 0x0");
        require(_wethAddress != address(0), "GMXDepositor: _wethAddress cannot be 0x0");
        require(_rewardTracker != address(0), "GMXDepositor: _rewardTracker cannot be 0x0");
        require(_wethAddress.isContract(), "GMXDepositor: _wethAddress is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        caller = _caller;
        wethAddress = _wethAddress;
        rewardTracker = _rewardTracker;
        platform = _platform;
        platformFee = 10;
    }

    /// @notice Buy fsGLP
    /// @param _token collateral token
    /// @param _amountIn collateral amount
    /// @return fsGlp address
    /// @return GLP amount
    function mint(address _token, uint256 _amountIn) public payable override onlyCaller returns (address, uint256) {
        require(_token != address(0), "GMXDepositor: _token cannot be 0x0");

        _harvest();

        if (_token == ZERO) {
            _wrapETH(_amountIn);

            _token = wethAddress;
        } else {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;
        }

        _approve(_token, executor, _amountIn);

        (address mintedToken, uint256 amountOut) = IGMXExecutor(executor).mint(_token, _amountIn);

        emit Mint(_token, _amountIn, amountOut);

        return (mintedToken, amountOut);
    }

    /// @notice sell fsGlp
    /// @param _tokenOut target token address
    /// @param _amountIn fsGlp amount
    /// @param _minOut minimum amount of token received
    /// @return received token amount
    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) public payable override onlyCaller returns (uint256) {
        _harvest();

        uint256 amountOut = IGMXExecutor(executor).withdraw(_tokenOut, _amountIn, _minOut);

        IERC20Upgradeable(_tokenOut).safeTransfer(msg.sender, amountOut);

        emit Withdraw(_tokenOut, _amountIn, amountOut);

        return amountOut;
    }

    function _harvest() internal returns (uint256) {
        uint256 rewards = IGMXExecutor(executor).claimRewards();

        if (rewards > 0) {
            uint256 fees;

            if (platform != address(0)) {
                fees = (rewards * platformFee) / FEE_DENOMINATOR;

                IERC20Upgradeable(wethAddress).safeTransfer(platform, fees);

                rewards = rewards - fees;
            }

            ClaimedReward storage claimedReward = claimedRewards[wethAddress];
            claimedReward.rewards = claimedReward.rewards + rewards;

            _approve(wethAddress, distributer, rewards);

            IDepositorRewardDistributor(distributer).distribute(rewards);

            emit Harvest(wethAddress, rewards, fees);
        }

        return rewards;
    }

    /// @notice harvest weth reward
    /// @return weth amount
    function harvest() public override nonReentrant onlyRewardTracker returns (uint256) {
        return _harvest();
    }

    /// @notice set execute contract for depositor
    /// @dev can only run once
    /// @param _executor contract address
    function setExecutor(address _executor) external onlyOwner {
        require(_executor != address(0), "GMXDepositor: _executor cannot be 0x0");
        require(executor == address(0), "GMXDepositor: Cannot run this function twice");
        executor = _executor;
    }

    /// @notice set weth reward distributor address
    /// @dev can only run once
    /// @param _distributer contract address
    function setDistributer(address _distributer) external onlyOwner {
        require(_distributer != address(0), "GMXDepositor: _distributer cannot be 0x0");
        require(distributer == address(0), "GMXDepositor: Cannot run this function twice");
        distributer = _distributer;
    }

    /// @notice set platform fee address
    /// @param _platform address
    function setPlatform(address _platform) external onlyOwner {
        platform = _platform;
    }

    /// @notice change platform fee address
    /// @dev 15% maximum
    /// @param _platformFee fee precision 100
    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= MAX_PLATFORM_FEE, "GMXDepositor: Maximum limit exceeded");

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
        require(msg.value == _amountIn, "GMXDepositor: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("GMXDepositor: Not allowed");
    }
}
