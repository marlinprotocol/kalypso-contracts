// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/* Interfaces */
import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
// import {IInflationRewardManager} from "../../interfaces/staking/IInflationRewardManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {IStakingPool} from "../../interfaces/staking/IStakingPool.sol";
import {IRewardDistributor} from "../../interfaces/staking/IRewardDistributor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Libraries */
import {Struct} from "../../lib/staking/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    /*===================================================================================================================*/
    /*================================================ state variable ===================================================*/
    /*===================================================================================================================*/

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    EnumerableSet.AddressSet private stakingPoolSet;

    address public jobManager;
    address public symbioticStaking;
    // address public inflationRewardManager;
    address public feeToken;
    // address public inflationRewardToken;

    // gaps in case we new vars in same file
    uint256[500] private __gap_1; 

    /*===================================================================================================================*/
    /*==================================================== mapping ======================================================*/
    /*===================================================================================================================*/

    mapping(address pool => Struct.PoolConfig config) private poolConfig;

    /*===================================================================================================================*/
    /*=================================================== modifier ======================================================*/
    /*===================================================================================================================*/

    modifier onlyJobManager() {
        require(msg.sender == jobManager, "StakingManager: Only JobManager");
        _;
    }

    modifier onlySymbioticStaking() {
        require(msg.sender == symbioticStaking, "StakingManager: Only SymbioticStaking");
        _;
    }

    /*===================================================================================================================*/
    /*================================================== initializer ====================================================*/
    /*===================================================================================================================*/

    function initialize(address _admin, address _jobManager, address _symbioticStaking, address _feeToken, address _inflationRewardToken) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_jobManager != address(0), "StakingManager: Invalid JobManager");
        jobManager = _jobManager;

        require(_feeToken != address(0), "StakingManager: Invalid FeeToken");
        feeToken = _feeToken;

        require(_symbioticStaking != address(0), "StakingManager: Invalid SymbioticStaking");
        symbioticStaking = _symbioticStaking;
    }

    /*===================================================================================================================*/
    /*==================================================== external =====================================================*/
    /*===================================================================================================================*/
    

    /*------------------------------------------------- Job Manager -----------------------------------------------------*/

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
    function onJobCompletion(uint256 _jobId, address _operator, uint256 _feeRewardAmount) external onlyJobManager {
        // update pending inflation reward
        // (uint256 timestampIdx, uint256 pendingInflationReward) = IInflationRewardManager(inflationRewardManager).updatePendingInflationReward(_operator);    

        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);

            if(!isEnabledPool(pool)) continue;

            uint256 poolFeeRewardAmount = _calcFeeRewardAmount(pool, _feeRewardAmount);

            IStakingPool(pool).onJobCompletion(_jobId, _operator, poolFeeRewardAmount);
        }

        // TODO: emit event
    }

    /*---------------------------------------------- Symbiotic Staking --------------------------------------------------*/

    /// @notice called by SymbioticStaking contract when slash result is submitted
    function onSlashResult(Struct.JobSlashed[] calldata _jobsSlashed) external onlySymbioticStaking {
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

    /*===================================================================================================================*/
    /*=================================================== public view ===================================================*/
    /*===================================================================================================================*/

    function isEnabledPool(address _pool) public view returns (bool) {
        return poolConfig[_pool].enabled;
    }

    function getPoolConfig(address _pool) external view returns (Struct.PoolConfig memory) {
        return poolConfig[_pool];
    }

    /*===================================================================================================================*/
    /*================================================== internal view ==================================================*/
    /*===================================================================================================================*/

    function _calcFeeRewardAmount(address _pool, uint256 _feeRewardAmount) internal view returns (uint256) {
        uint256 poolShare = poolConfig[_pool].share;
        
        uint256 poolFeeRewardAmount = _feeRewardAmount > 0 ? Math.mulDiv(_feeRewardAmount, poolShare, 1e18) : 0;

        return poolFeeRewardAmount;
    }

    /*===================================================================================================================*/
    /*===================================================== admin =======================================================*/
    /*===================================================================================================================*/

    /// @notice add new staking pool
    /// @dev share and enabled must be set
    function addStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.add(_stakingPool);

        emit StakingPoolAdded(_stakingPool);
    }

    function removeStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.remove(_stakingPool);

        emit StakingPoolRemoved(_stakingPool);
    }

    function setJobManager(address _jobManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobManager = _jobManager;

        emit JobManagerSet(_jobManager);
    }

    function setSymbioticStaking(address _symbioticStaking) external onlyRole(DEFAULT_ADMIN_ROLE) {
        symbioticStaking = _symbioticStaking;

        emit SymbioticStakingSet(_symbioticStaking);
    }

    function setFeeToken(address _feeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeToken = _feeToken;

        emit FeeTokenSet(_feeToken);
    }

    function setEnabledPool(address _pool, bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(stakingPoolSet.contains(_pool), "StakingManager: Pool not in set");

        poolConfig[_pool].enabled = _enabled;

        emit PoolEnabledSet(_pool, _enabled);
    }

    // when job is closed, the reward will be distributed based on the share
    function setPoolRewardShare(address[] calldata _pools, uint256[] calldata _shares)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_pools.length == _shares.length || _pools.length == stakingPoolSet.length(), "Invalid Length");

        uint256 sum = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            poolConfig[_pools[i]].share = _shares[i];

            sum += _shares[i];
        }

        // as the weight is in percentage, the sum of the shares should be 1e18 (100%)
        require(sum == 1e18, "Invalid Shares");

        emit PoolRewardShareSet(_pools, _shares);
    }

    /*===================================================================================================================*/
    /*==================================================== override =====================================================*/
    /*===================================================================================================================*/

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
