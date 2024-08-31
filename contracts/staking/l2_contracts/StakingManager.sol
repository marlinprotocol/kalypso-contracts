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
    INativeStaking {
    // TODO: Staking Pool Set
    // TODO: Staking Pool flag   

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
    function slashJob(address _jobId, address _vault, uint256 _captureTimestamp, uint256 _amount, address _rewardAddress) external {
        // TODO: only slashingManager
    }

    // create job and lock stakes (operator self stake, some portion of native stake and symbiotic stake)
    // locked stake will be unlocked after an epoch if no slas result is submitted
    function onJobCreation(address _jobId, address _operator, uint256 _amount) external {
        // TODO: only jobManager
    }

    // called when job is completed to unlock the locked stakes
    function onJobCompletion(address _jobId) external {
        // TODO: only jobManager
    }

    // called when Staked/Unstaked in the Staking Pool (Native Staking, Symbiotic Staking)
    function updateStake(address operator, address token, uint256 amount) external {
        // TODO: only Staking Pool
    }

    // when certain period has passed after the lock and no slash result is submitted, this can be unlocked
    function unlockStake(address _jobId) external { }


    /*======================================== Getters ========================================*/

    // check if the job is slashable and can be sent to the slashing manager
    // this only tells if the deadline for proof submission has passed
    // so even when this function returns true and transaction submitted to L1 can be reverted
    // when someone already has submitted the proof
    function isSlashable(address _jobId) external view returns(bool) {
        // TODO
    }

    // for all operators
    function getLatestStakeInfo() public {
        // TODO
    }

    function getLatestStakeInfoAt(uint256 timestamp) public {
        // TODO
    }

    // for a specific operator
    function getLatestStakeInfo(address operator) public {
        // TODO
    }

    function getStakeInfoAt(address operator, address token, uint256 timestamp) public returns(uint256) {
        // TODO
    }

    // TODO: function that consolidates the staking information from both Native Staking and Symbiotic Staking and returns the total stake amount

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