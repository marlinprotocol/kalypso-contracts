// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IJobManager} from "../../interfaces/staking/IJobManager.sol";
import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";

/* 
    JobManager contract is responsible for creating and managing jobs.
    Staking Manager contract is responsible for locking/unlocking tokens and distributing rewards.
 */
contract JobManager is 
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IJobManager
{
    using SafeERC20 for IERC20;

    address public stakingManager;
    address public feeToken;
    uint256 public jobDuration = 1 days;

    struct JobInfo {
        address requester;
        address operator;
        uint256 feePaid;
        uint256 deadline;
    }

    mapping(uint256 jobId => JobInfo jobInfo) public jobs;
    uint256 feePaid;

    function initialize(address _admin) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }


    // TODO: check paramter for job details
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount) external nonReentrant {
        // TODO: called only from Kalypso Protocol

        IERC20(feeToken).safeTransferFrom(_requester, address(this), _feeAmount);
        
        // stakeToken and lockAmount will be decided in each pool
        jobs[_jobId] = JobInfo({
            requester: _requester,
            operator: _operator,
            feePaid: _feeAmount,
            deadline: block.timestamp + jobDuration
        });
    
        // TODO: call creation function in StakingManager
        IStakingManager(stakingManager).onJobCreation(_jobId, _operator);
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 jobId, bytes calldata proof) public nonReentrant {
        require(block.timestamp <= jobs[jobId].deadline, "Job Expired");

        _verifyProof(jobId, proof);

        IStakingManager(stakingManager).onJobCompletion(jobId); // unlock stake
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata jobIds, bytes[] calldata proofs) external nonReentrant {
        require(jobIds.length == proofs.length, "Invalid Length");

        // TODO: close job and distribute rewards

        uint256 len = jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = jobIds[idx];
            require(block.timestamp <= jobs[jobId].deadline, "Job Expired");
            
            _verifyProof(jobId, proofs[idx]);

            // TODO: let onJobCompletion also accept array of jobIds
            IStakingManager(stakingManager).onJobCompletion(jobId); // unlock stake
        }

    }

    function refundFee(uint256 jobId) external nonReentrant {
        require(block.timestamp > jobs[jobId].deadline, "Job not Expired");
        require(jobs[jobId].requester == msg.sender, "Not Requester");

        // TODO: refund fee
        jobs[jobId].feePaid = 0;

        IERC20(feeToken).safeTransfer(jobs[jobId].requester, jobs[jobId].feePaid);
        // TODO: emit event
    }

    function _verifyProof(uint256 jobId, bytes calldata proof) internal {
        // TODO: verify proof
    }

    function setStakingManager(address _stakingManager) external {
        stakingManager = _stakingManager;
    }


    /*======================================== Overrides ========================================*/

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