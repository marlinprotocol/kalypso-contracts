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
import {IKalypsoStaking} from "../../interfaces/staking/IKalypsoStaking.sol";

contract StakingManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
    // INativeStaking
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // TODO: Staking Pool Set
    EnumerableSet.AddressSet private stakingPoolSet;

    // TODO: Staking Pool flag
    // mapping(address pool => bool isEnabled) private stakingPoolStatus;
    // mapping(address pool => uint256 weight) private stakingPoolWeight;

    mapping(address pool => PoolConfig config) private poolConfig;

    // TODO: getter for retreiving the each pool's lock amount
    mapping(uint256 jobId => uint256 lockAmount) private lockInfo; // total lock amount and unlock timestamp

    uint256 unlockEpoch;
    uint256 stakeDataTransmitterShare;

    struct PoolConfig {
        uint256 weight;
        uint256 minStake;
        bool enabled;
    }

    // operator, lockToken, lockAmount should be stored in JobManager
    struct StakeLockInfo {
        uint256 totalLockAmount; 
        uint256 unlockTimestamp;
    }

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // create job and lock stakes (operator self stake, some portion of native stake and symbiotic stake)
    // locked stake will be unlocked after an epoch if no slas result is submitted

    // note: data related to the job should be stored in JobManager (e.g. operator, lockToken, lockAmount, proofDeadline)
    function onJobCreation(uint256 _jobId, address _token, uint256 _delegatedStakeLock, uint256 _selfStakeLock) external {
        // TODO: only jobManager

        // TODO: lock selfstake, Native Staking delegated stake, Symbiotic Stake

        uint256 len = stakingPoolSet.length();

        for(uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);
            
            if(!isEnabledPool(pool)) continue; // skip if the pool is not enabled
            if(!IKalypsoStaking(pool).isSupportedToken(_token)) continue; // skip if the token is not supported by the pool
            
            uint256 poolStake = IKalypsoStaking(pool).getPoolStake(pool, _token); 
            uint256 minStake = poolConfig[pool].minStake;

            // skip if the pool stake is less than the minStake
            //? case when lockAmount > minStake?
            uint256 lockAmount = 0;
            if(poolStake >= minStake) { 
                uint256 poolLockAmount = _calcLockAmount(poolStake, pool); // TODO: lock amount will be fixed
                lockAmount += poolLockAmount;
                IKalypsoStaking(pool).lockStake(_jobId, _token, _selfStakeLock, _delegatedStakeLock);
            }
        }
    }

    // TODO: fix this
    function _calcLockAmount(uint256 amount, address pool) internal view returns (uint256) {
        uint256 weight = poolConfig[pool].weight;

        return (amount * weight) / 10000;
    }

    // TODO
    // function getPoolStake(address _pool, address _operator, address _token) internal view returns (uint256) {
    //     return IKalypsoStaking(_pool).getStakeAmount(_operator, _token);
    // }

    // called when job is completed to unlock the locked stakes
    function onJobCompletion(uint256 _jobId) external {
        // TODO: only jobManager

        // TODO: unlock the locked stakes
        // _unlockStake(_jobId);
    }

    /*======================================== Getters ========================================*/

    // check if the job is slashable and can be sent to the slashing manager
    // this only tells if the deadline for proof submission has passed
    // so even when this function returns true and transaction submitted to L1 can be reverted
    // when someone already has submitted the proof
    function isSlashable(address _jobId) external view returns (bool) {
        // TODO: check if the proof was submitted before the deadline, so need to query jobmanager
    }

    function isEnabledPool(address _pool) public view returns (bool) {
        return poolConfig[_pool].enabled;
    }

    /*======================================== Getter for Staking ========================================*/



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

    // when job is closed, the reward will be distributed based on the share
    function setShare(address[] calldata _pools, uint256[] calldata _shares, uint256 _transmitterShare) external  {
        // TODO: only admin
        require(_pools.length == _shares.length, "Invalid Length");

        uint256 sum = 0;
        for(uint256 i = 0; i < _shares.length; i++) {
            sum += _shares[i];
        }
        sum += _transmitterShare;

        // as the weight is in percentage, the sum of the shares should be 10000
        // TODO: sum of enabled pools should be 10000
        require(sum == 10000, "Invalid Shares");

        for(uint256 i = 0; i < _pools.length; i++) {
            poolConfig[_pools[i]].weight = _shares[i];
        }
        stakeDataTransmitterShare = _transmitterShare;
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
