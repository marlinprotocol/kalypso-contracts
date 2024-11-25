// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IJobManager {
    /* JobCreation */
    event JobCreated(uint256 indexed jobId, address indexed requester, address indexed operator, uint256 feeAmount);
    event ProofSubmitted(uint256 indexed jobId, address indexed operator, bytes proof);
    event FeeRefunded(uint256 indexed jobId, address indexed requester, uint256 feeAmount);
    event JobCompleted(uint256 indexed jobId, address indexed operator, uint256 feeRewardAmount);

    /* contracts set */
    event StakingManagerSet(address indexed stakingManager);
    event SymbioticStakingSet(address indexed symbioticStaking);
    event SymbioticStakingRewardSet(address indexed symbioticStakingReward);
    event FeeTokenSet(address indexed feeToken);
    event JobDurationSet(uint256 jobDuration);
    event OperatorRewardShareSet(address indexed operator, uint256 rewardShare);

    /* fee reward */
    event OperatorFeeRewardAdded(address indexed operator, uint256 feeRewardAmount);
    event OperatorFeeRewardClaimed(address indexed operator, uint256 feeRewardAmount);
    event TransmitterFeeRewardAdded(address indexed transmitter, uint256 feeRewardAmount);
    event TransmitterFeeRewardClaimed(address indexed transmitter, uint256 feeRewardAmount);

    function operatorFeeRewards(address _operator) external view returns (uint256);

    function transmitterFeeRewards(address _transmitter) external view returns (uint256);
    
    function createJob(uint256 _jobId, address _requester, address _operator, uint256 _feeAmount) external;

    function submitProof(uint256 jobId, bytes calldata proof) external;

    function submitProofs(uint256[] calldata jobIds, bytes[] calldata proofs) external;

    // function refundFee(uint256 jobId) external;

    function operatorRewardShares(address _operator) external view returns (uint256);

    function claimOperatorFeeReward() external;

    function claimTransmitterFeeReward() external;

    function distributeTransmitterFeeReward(address _transmitter, uint256 _feeRewardAmount) external;
    
}