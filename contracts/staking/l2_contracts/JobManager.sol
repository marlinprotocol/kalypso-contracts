// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingManager} from "../../interfaces/staking/IStakingManager.sol";

/* 
    JobManager contract is responsible for creating and managing jobs.
    Staking Manager contract is responsible for locking/unlocking tokens and distributing rewards.
 */
contract JobManager {
    uint256 constant JOB_DURATION = 1 days;

    IStakingManager stakingManager;

    struct JobInfo {
        address operator;
        uint256 deadline;
    }

    mapping(uint256 => JobInfo) public jobs;

    // TODO: check paramter for job details
    function createJob(uint256 jobId, address operator) external {
        // TODO: called only from Kalypso Protocol
        
        // stakeToken and lockAmount will be decided in each pool
        jobs[jobId] = JobInfo({
            operator: operator,
            deadline: block.timestamp + JOB_DURATION
        });
    
        // TODO: call creation function in StakingManager
        stakingManager.onJobCreation(jobId, operator);
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 jobId, bytes calldata proof) public {
        require(block.timestamp <= jobs[jobId].deadline, "Job Expired");

        _verifyProof(jobId, proof);

        stakingManager.onJobCompletion(jobId); // unlock stake
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata jobIds, bytes[] calldata proofs) external {
        require(jobIds.length == proofs.length, "Invalid Length");

        // TODO: close job and distribute rewards

        uint256 len = jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            uint256 jobId = jobIds[idx];
            require(block.timestamp <= jobs[jobId].deadline, "Job Expired");
            
            _verifyProof(jobId, proofs[idx]);

            // TODO: let onJobCompletion also accept array of jobIds
            stakingManager.onJobCompletion(jobId); // unlock stake
        }

    }

    function refundFee(uint256 jobId) external {
        require(block.timestamp > jobs[jobId].deadline, "Job not Expired");

        // TODO: refund fee

        // TODO: emit event
    }

    // TODO: implement manual slash

    function _verifyProof(uint256 jobId, bytes calldata proof) internal {
        // TODO: verify proof
    }

    function setStakingManager(address _stakingManager) external {
        stakingManager = IStakingManager(_stakingManager);
    }
}