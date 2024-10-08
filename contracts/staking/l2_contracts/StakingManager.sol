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

import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {IStakingPool} from "../../interfaces/staking/IStakingPool.sol";
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

import {Struct} from "../../lib/staking/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract StakingManager is
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IStakingManager
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet private stakingPoolSet;

    address public jobManager;
    address public feeToken;
    address public inflationRewardToken;

    mapping(address pool => Struct.PoolConfig config) private poolConfig;
    mapping(address pool => uint256 weight) private stakingPoolWeight;

    modifier onlyJobManager() {
        require(msg.sender == jobManager, "StakingManager: Only JobManager");
        _;
    }

    function initialize(address _admin, address _jobManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        jobManager = _jobManager;
    }

    // create job and lock stakes (operator self stake, some portion of native stake and symbiotic stake)
    // locked stake will be unlocked after an epoch if no slas result is submitted

    // note: data related to the job should be stored in JobManager (e.g. operator, lockToken, lockAmount, proofDeadline)
    function onJobCreation(uint256 _jobId, address _operator) external onlyJobManager {
        uint256 len = stakingPoolSet.length();

        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);
            if (!isEnabledPool(pool)) continue; // skip if the pool is not enabled

            IStakingPool(pool).lockStake(_jobId, _operator);
        }
    }

    // called when job is completed to unlock the locked stakes
    function onJobCompletion(uint256 _jobId, address _operator, uint256 _feePaid, uint256 _inflationRewardAmount) external onlyJobManager {
        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);

            (uint256 poolFeeRewardAmount, uint256 poolInflationRewardAmount) = _calcRewardAmount(pool, _feePaid, _inflationRewardAmount);

            IStakingPool(pool).onJobCompletion(_jobId, _operator, poolFeeRewardAmount, poolInflationRewardAmount);
        }
        // TODO: emit event
    }

    /// @notice called by SymbioticStaking contract when slash result is submitted
    function onSlashResult(Struct.JobSlashed[] calldata _jobsSlashed) external onlyJobManager {
        // msg.sender will most likely be SymbioticStaking contract
        require(stakingPoolSet.contains(msg.sender), "StakingManager: Invalid Pool");

        // refund fee to the requester
        for(uint256 i = 0; i < _jobsSlashed.length; i++) {
            // this can be done manually in the JobManager contract
            // refunds nothing if already refunded
            IJobManager(jobManager).refundFee(_jobsSlashed[i].jobId);
        }

        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);
            IStakingPool(pool).slash(_jobsSlashed);
        }
    }

    function distributeInflationReward(address _operator, uint256 _rewardAmount) external onlyJobManager {
        if(_rewardAmount == 0) return;

        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);

            (, uint256 poolRewardAmount) = _calcRewardAmount(pool, 0, _rewardAmount);
            IERC20(inflationRewardToken).safeTransfer(pool, poolRewardAmount);

            // TODO
            IStakingPool(pool).distributeInflationReward(_operator, poolRewardAmount);
        }
    }

    function _calcRewardAmount(address _pool, uint256 _feeRewardAmount, uint256 _inflationRewardAmount) internal view returns (uint256, uint256) {
        uint256 poolWeight = poolConfig[_pool].weight;
        
        uint256 poolFeeRewardAmount = _feeRewardAmount > 0 ? Math.mulDiv(_feeRewardAmount, poolWeight, 1e18) : 0;
        uint256 poolInflationRewardAmount = _inflationRewardAmount > 0 ? Math.mulDiv(_inflationRewardAmount, poolWeight, 1e18) : 0;

        return (poolFeeRewardAmount, poolInflationRewardAmount);
    }

    /*======================================== Getters ========================================*/
    function isEnabledPool(address _pool) public view returns (bool) {
        return poolConfig[_pool].enabled;
    }

    /*======================================== Admin ========================================*/

    // add new staking pool
    function addStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.add(_stakingPool);

        // TODO: emit event
    }

    function removeStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.remove(_stakingPool);

        // TODO: emit event
    }

    function setJobManager(address _jobManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobManager = _jobManager;

        // TODO: emit event
    }

    // when job is closed, the reward will be distributed based on the share
    function setShare(address[] calldata _pools, uint256[] calldata _shares)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_pools.length == _shares.length || _pools.length == stakingPoolSet.length(), "Invalid Length");

        uint256 sum = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            poolConfig[_pools[i]].weight = _shares[i];

            sum += _shares[i];
        }

        // as the weight is in percentage, the sum of the shares should be 1e18 (100%)
        require(sum == 1e18, "Invalid Shares");
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
