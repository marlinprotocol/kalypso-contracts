// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* Contracts */
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/* Interfaces */
import {IProofMarketplace} from "../../interfaces/IProofMarketplace.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";
import {IStakingPool} from "../../interfaces/staking/IStakingPool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Libraries */
import {Struct} from "../../lib/Struct.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Error} from "../../lib/Error.sol";

contract StakingManager is
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IStakingManager
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    //---------------------------------------- Constant start ----------------------------------------//

    bytes32 public constant PROVER_MANAGER_ROLE = keccak256("PROVER_MANAGER"); // TODO: fix to PROVER_MANAGER
    bytes32 public constant SYMBIOTIC_STAKING_ROLE = keccak256("SYMBIOTIC_STAKING");

    //---------------------------------------- Constant end ----------------------------------------//

    //---------------------------------------- State Variable start ----------------------------------------//

    EnumerableSet.AddressSet private stakingPoolSet;

    address public proofMarketplace;
    address public symbioticStaking;
    address public feeToken;

    mapping(address pool => Struct.PoolConfig config) private poolConfig;

    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    //---------------------------------------- State Variable end ----------------------------------------//

    //---------------------------------------- Init start ----------------------------------------//
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _proofMarketplace, address _symbioticStaking, address _feeToken) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        require(_proofMarketplace != address(0), Error.InvalidStakingManager());
        proofMarketplace = _proofMarketplace;
        emit ProofMarketplaceSet(_proofMarketplace);

        require(_feeToken != address(0), Error.InvalidFeeToken());
        feeToken = _feeToken;
        emit FeeTokenSet(_feeToken);

        require(_symbioticStaking != address(0), Error.InvalidSymbioticStaking());
        symbioticStaking = _symbioticStaking;
        emit SymbioticStakingSet(_symbioticStaking);

        // TODO: Add ROLE_SETTER role
    }

    //---------------------------------------- Init end ----------------------------------------//

    //---------------------------------------- PROVER_MANAGER_ROLE start ----------------------------------------//

    /// @notice lock stake for the task for all enabled pools
    /// @dev called by ProofMarketplace contract when a task is created
    function onTaskAssignment(uint256 _bidId, address _prover) external onlyRole(PROVER_MANAGER_ROLE) {
        uint256 len = stakingPoolSet.length();

        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);
            if (!isEnabledPool(pool)) continue; // skip if the pool is not enabled

            IStakingPool(pool).lockStake(_bidId, _prover);
        }
    }

    /**
     * @notice  called when task is completed to unlock the locked stakes
     * @dev     called by ProofMarketplace contract when a task is completed
     */
    function onTaskCompletion(uint256 _bidId, address _prover, uint256 _feeRewardAmount) external onlyRole(PROVER_MANAGER_ROLE) {
        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);

            if(!isEnabledPool(pool)) continue;

            uint256 poolFeeRewardAmount = _calcFeeRewardAmount(pool, _feeRewardAmount);

            IStakingPool(pool).onTaskCompletion(_bidId, _prover, poolFeeRewardAmount);
        }
        
        // TODO: emit event?
    }

    function _calcFeeRewardAmount(address _pool, uint256 _feeRewardAmount) internal view returns (uint256) {
        uint256 poolShare = poolConfig[_pool].share;
        
        uint256 poolFeeRewardAmount = _feeRewardAmount > 0 ? Math.mulDiv(_feeRewardAmount, poolShare, 1e18) : 0;

        return poolFeeRewardAmount;
    }

    //---------------------------------------- PROVER_MANAGER_ROLE end ----------------------------------------//

    //---------------------------------------- SYMBIOTIC_STAKING_ROLE start ----------------------------------------//


    /// @notice called by SymbioticStaking contract when slash result is submitted
    function onSlashResultSubmission(Struct.TaskSlashed[] calldata _tasksSlashed) external onlyRole(SYMBIOTIC_STAKING_ROLE) {
        // msg.sender will most likely be SymbioticStaking contract
        require(stakingPoolSet.contains(msg.sender), Error.InvalidPool());

        uint256[] memory bidIds = new uint256[](_tasksSlashed.length);
        for(uint256 i = 0; i < _tasksSlashed.length; i++) {
            bidIds[i] = _tasksSlashed[i].bidId;
        }

        // this will do nothing for bidIds that are already refunded
        IProofMarketplace(proofMarketplace).refundFees(bidIds);

        uint256 len = stakingPoolSet.length();
        for (uint256 i = 0; i < len; i++) {
            address pool = stakingPoolSet.at(i);
            // this will do nothing for bidIds that are already slashed (if same data has been submitted before)
            IStakingPool(pool).slash(_tasksSlashed);
        }
    }

    //---------------------------------------- SYMBIOTIC_STAKING_ROLE end ----------------------------------------//

    //---------------------------------------- Getter start ----------------------------------------//

    function isEnabledPool(address _pool) public view returns (bool) {
        return poolConfig[_pool].enabled;
    }

    function getPoolConfig(address _pool) external view returns (Struct.PoolConfig memory) {
        return poolConfig[_pool];
    }

    //---------------------------------------- Getter end ----------------------------------------//

    //---------------------------------------- DEFAULT_ADMIN_ROLE start ----------------------------------------//

    /// @notice add new staking pool
    /// @dev 
    function addStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.add(_stakingPool);

        emit StakingPoolAdded(_stakingPool);
    }

    /// @notice remove staking pool
    function removeStakingPool(address _stakingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingPoolSet.remove(_stakingPool);
        delete poolConfig[_stakingPool];

        emit StakingPoolRemoved(_stakingPool);
    }

    function setProofMarketplace(address _proofMarketplace) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proofMarketplace = _proofMarketplace;

        emit ProofMarketplaceSet(_proofMarketplace);
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
        require(stakingPoolSet.contains(_pool), Error.PoolAlreadyExists());

        poolConfig[_pool].enabled = _enabled;

        emit PoolEnabledSet(_pool, _enabled);
    }

    // when task is completed, the reward will be distributed based on the share
    function setPoolRewardShare(address[] calldata _pools, uint256[] calldata _shares)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_pools.length == _shares.length && _pools.length == stakingPoolSet.length(), Error.InvalidLength());

        uint256 sum = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            poolConfig[_pools[i]].share = _shares[i];

            sum += _shares[i];

            emit PoolRewardShareSet(_pools[i], _shares[i]);
        }

        // as the weight is in percentage, the sum of the shares should be 1e18 (100%)
        require(sum == 1e18, Error.InvalidShares());
    }

    function emergencyWithdraw(address _token, address _to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), Error.ZeroTokenAddress());
        require(_to != address(0), Error.ZeroToAddress());

        IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
    }

    //---------------------------------------- DEFAULT_ADMIN_ROLE end ----------------------------------------//

    //---------------------------------------- Override start ----------------------------------------//

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    function _authorizeUpgrade(address /*account*/ ) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //---------------------------------------- Override end ----------------------------------------//
}
