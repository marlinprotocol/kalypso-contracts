// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IJobManager {
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount) external;
    
    function submitProof(uint256 jobId, bytes calldata proof) external;

    function refundFee(uint256 jobId) external;

    // function updateInflationReward(address _operator) external;
}