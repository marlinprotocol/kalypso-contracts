// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {INativeStaking} from "../../interfaces/staking/INativeStaking.sol";

contract StakingManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    INativeStaking
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // TODO: Staking Pool Set
    EnumerableSet.AddressSet private stakingPoolSet;

    // TODO: Staking Pool flag
    // mapping(address pool => bool isEnabled) private stakingPoolStatus;
    // mapping(address pool => uint256 weight) private stakingPoolWeight;

    mapping(address pool => PoolConfig config) private poolConfig;
    mapping(uint256 jobId => mapping(address pool => LockInfo lockInfo)) private lockInfo;

    uint256 unlockEpoch;

    struct PoolConfig {
        uint256 weight;
        uint256 minStake;
        bool isEnabled;
    }

    // operator, lockToken, lockAmount should be stored in JobManager
    struct LockInfo {
        uint256 lockAmount; // locked amount for the pool
        uint256 unlockTimestamp;
    }

    // TODO: integration with Slasher

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // TODO: Self stake is given to the slasher while the rest of the stakers is burnt when slashed
    // TODO: check necessary params
    function slashJob(
        address _jobId,
        address _vault,
        uint256 _captureTimestamp,
        uint256 _amount,
        address _rewardAddress
    ) external {
        // TODO: only slashingManager
    }

    // create job and lock stakes (operator self stake, some portion of native stake and symbiotic stake)
    // locked stake will be unlocked after an epoch if no slas result is submitted

    // note: data related to the job should be stored in JobManager (e.g. operator, lockToken, lockAmount, proofDeadline)
    function onJobCreation(address _jobId, address _operator, address token, uint256 _lockAmount) external {
        // TODO: only jobManager

        // TODO: lock operator selfstake

        address[] memory enabledPoolList = getEnabledPoolList();

        uint256 len = enabledPoolList.length;
        for(uint256 i = 0; i < len; i++) {
            pool = enabledPoolList[i];

            // skip if the token is not supported by the pool
            if(!IKalypsoStakingPool(pool).isSupportedToken(token)) continue;
            
            uint256 poolStake = getPoolStake(pool, _operator, token);
            uint256 minStake = poolConfig[pool].minStake;

            // skip if the pool stake is less than the minStake
            if(poolStake >= minStake) {
                // lock the stake
                uint256 lockAmount = _calcLockAmount(poolStake, poolConfig[pool].weight); // TODO: need to check formula for calculation
                _lockStake(pool, lockAmount);
            }
        }
    }

    function _lockStake(address _jobId, uint256 amount) internal {
        lockInfo[_jobId].lockAmount += amount;
        lockInfo[_jobId].unlockTimestamp = block.timestamp + unlockEpoch;
    }

    function _unlockStake(address _jobId) internal {
        lockInfo[_jobId].lockAmount = 0;
        lockInfo[_jobId].unlockTimestamp = 0;
    }

    // called when job is completed to unlock the locked stakes
    function onJobCompletion(address _jobId) external {
        // TODO: only jobManager

        // TODO: unlock the locked stakes
    }

    // when certain period has passed after the lock and no slash result is submitted, this can be unlocked
    function unlockStake(address _jobId) external {
        
    }

    /*======================================== Getters ========================================*/

    // check if the job is slashable and can be sent to the slashing manager
    // this only tells if the deadline for proof submission has passed
    // so even when this function returns true and transaction submitted to L1 can be reverted
    // when someone already has submitted the proof
    function isSlashable(address _jobId) external view returns (bool) {
        // TODO: check if the proof was submitted before the deadline
    }

    /*======================================== Getter for Staking ========================================*/

    function _calcLockAmount(uint256 amount, uint256 weight) internal pure returns (uint256) {
        return (amount * weight) / 10000; // TODO: need to check formula for calculation (probably be the share)
    }


    function getEnabledPoolList() public view returns (address[] memory enabledPoolList) {
        uint256 len = stakingPoolSet.length;
        for(uint256 i = 0; i < len; i++) {
            pool = stakingPoolSet.at(i);
            
            if(poolConfig[pool].isEnabled) {
                enabledPoolList.push(pool);
            }
        }
    }


    /*======================================== Admin ========================================*/

    // add new staking pool
    function addStakingPool(address _stakingPool) external {
        // TODO: onlyAdmin
    }

    function removeStakingPool(address _stakingPool) external {
        // TODO: onlyAdmin
    }

    function setStakingPoolStatus(address _stakingPool, bool _status) external {
        // TODO: onlyAdmin
    }

    function setSlashingManager(address _slashingManager) external {
        // TODO: only admin
    }

    // TODO: integration with JobManager
    function setJobManager(address _jobManager) external {
        // TODO: only admin
    }

    // TODO: interaction with Price Oracle
    function setPriceOracle(address _priceOracle) external {
        // TODO
    }

    function setUnlockEpoch(uint256 _unlockEpoch) external {
        // TODO: check if the unlockEpoch is longer than the proofDeadline
    }

    /*======================================== Override ========================================*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
