// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { ICommonReward } from "./interfaces/ICommonReward.sol";
import { IDepositorRewardDistributor } from "./interfaces/IDepositorRewardDistributor.sol";

/* 
DepositorRewardDistributor is the distributor for Depositor, mainly used to distribute profits to extra rewards. 
The distribution ratio is calculated based on the percentage of staking tokens, 
and can be referred to in the distribute function.
*/

contract DepositorRewardDistributor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IDepositorRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    /* 
    WETH VaultRewardDistributor [Credit token] 
    USDT VaultRewardDistributor [Credit token] 
    USDC VaultRewardDistributor [Credit token]  
    WBTC VaultRewardDistributor [Credit token]  
    DAI VaultRewardDistributor  [Credit token]  
    LINK VaultRewardDistributor [Credit token] 
    UNI VaultRewardDistributor  [Credit token]  
    FRAX VaultRewardDistributor [Credit token] 
    collateralReward            [Credit token]
    */
    uint256 private constant MAX_EXTRA_REWARDS_SIZE = 12;

    address public stakingToken;
    address public rewardToken;
    address[] public extraRewards;

    mapping(address => bool) private distributors;

    modifier onlyDistributors() {
        require(isDistributor(msg.sender), "DepositorRewardDistributor: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _rewardToken, address _stakingToken) external initializer {
        require(_rewardToken != address(0), "DepositorRewardDistributor: _rewardToken cannot be 0x0");
        require(_stakingToken != address(0), "DepositorRewardDistributor: _stakingToken cannot be 0x0");

        require(_rewardToken.isContract(), "DepositorRewardDistributor: _rewardToken is not a contract");
        require(_stakingToken.isContract(), "DepositorRewardDistributor: _stakingToken is not a contract");

        __ReentrancyGuard_init();
        __Ownable_init();

        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
    }

    /// @notice extra reward contract length
    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    /// @notice add extra reward contract
    /// @dev can add CollateralReward, VaultRewardDistributor
    /// @param _reward contract address
    function addExtraReward(address _reward) external onlyOwner returns (bool) {
        require(_reward != address(0), "DepositorRewardDistributor: _reward cannot be 0x0");
        require(ICommonReward(_reward).stakingToken() == stakingToken, "DepositorRewardDistributor: Mismatched staking token");
        require(ICommonReward(_reward).rewardToken() == rewardToken, "DepositorRewardDistributor: Mismatched reward token");
        require(extraRewards.length < MAX_EXTRA_REWARDS_SIZE, "DepositorRewardDistributor: Maximum limit exceeded");

        extraRewards.push(_reward);

        emit AddExtraReward(_reward);

        return true;
    }

    /// @notice empty extra reward array
    function clearExtraRewards() external onlyOwner {
        delete extraRewards;

        emit ClearExtraRewards();
    }

    /// @notice add distributor
    /// @param _distributor distributor address
    function addDistributor(address _distributor) public onlyOwner {
        require(_distributor != address(0), "DepositorRewardDistributor: _distributor cannot be 0x0");
        require(!isDistributor(_distributor), "DepositorRewardDistributor: _distributor is already distributor");

        distributors[_distributor] = true;

        emit NewDistributor(msg.sender, _distributor);
    }

    /// @notice add distributors
    /// @param _distributors distributors array
    function addDistributors(address[] calldata _distributors) external onlyOwner {
        for (uint256 i = 0; i < _distributors.length; i++) {
            addDistributor(_distributors[i]);
        }
    }

    /// @notice remove distributor
    /// @param _distributor distributor address
    function removeDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "DepositorRewardDistributor: _distributor cannot be 0x0");
        require(isDistributor(_distributor), "DepositorRewardDistributor: _distributor is not the distributor");

        distributors[_distributor] = false;

        emit RemoveDistributor(msg.sender, _distributor);
    }

    /// @notice judge if its distributor
    /// @param _distributor distributor address
    /// @return bool value
    function isDistributor(address _distributor) public view returns (bool) {
        return distributors[_distributor];
    }

    /// @notice reward distribution
    /// @dev the distribution function will transfer from the caller to rewards
    /// @param _rewards reward amount
    function distribute(uint256 _rewards) external override nonReentrant onlyDistributors {
        require(_rewards > 0, "VaultRewardDistributor: _rewards cannot be 0");

        IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

        _rewards = IERC20Upgradeable(rewardToken).balanceOf(address(this));

        uint256 totalSupply = IERC20Upgradeable(stakingToken).totalSupply();

        if (totalSupply > 0) {
            for (uint256 i = 0; i < extraRewards.length; i++) {
                uint256 balance = IERC20Upgradeable(stakingToken).balanceOf(extraRewards[i]);

                if (balance > 0) {
                    uint256 ratio = (balance * PRECISION) / totalSupply;
                    uint256 amounts = (_rewards * ratio) / PRECISION;

                    _approve(rewardToken, extraRewards[i], amounts);

                    ICommonReward(extraRewards[i]).distribute(amounts);

                    emit Distribute(extraRewards[i], _rewards);
                }
            }
        }
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("DepositorRewardDistributor: Not allowed");
    }
}
