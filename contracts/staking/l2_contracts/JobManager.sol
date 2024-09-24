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
        address lockToken;
        uint256 lockedAmount; // this will go to slasher if the proof is not submitted before deadline
        uint256 deadline;
        address dataTransmitter; //
    }

    mapping(uint256 => JobInfo) public jobs;

    function createJob(uint256 jobId, address operator) external {
        // TODO: called only from Kalypso Protocol
        
        // TODO: create a job and record StakeData Transmitter who submitted capture timestamp
    

        // TODO: call creation function in StakingManager
        stakingManager.onJobCreation(jobId, operator); // lock stake
    }

    /**
     * @notice Submit Single Proof
     */
    function submitProof(uint256 jobId, bytes calldata proof) public {
        _verifyProof(jobId, proof);
    }

    /**
     * @notice Submit Multiple proofs in single transaction
     */
    function submitProofs(uint256[] calldata jobIds, bytes[] calldata proofs) external {
        require(jobIds.length == proofs.length, "Invalid Length");


        // TODO: close job and distribute rewards
        uint256 len = jobIds.length;
        for (uint256 idx = 0; idx < len; idx++) {
            _verifyProof(jobIds[idx], proofs[idx]);

            uint256 jobId;
            stakingManager.onJobCompletion(jobId, jobs[jobId].lockToken); // unlock stake
        }

    }

    function _verifyProof(uint256 jobId, bytes calldata proof) internal {
        // TODO
    }

    function setStakingManager(address _stakingManager) external {
        stakingManager = IStakingManager(_stakingManager);
    }
}