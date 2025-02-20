// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

library Error {
    // Administrative and Miscellaneous Errors
    error OnlyAdminCanCall();
    error CannotBeAdminLess();
    error CannotBeZero();
    error CannotBeSlashed();
    error InsufficientStakeToLock();
    error EnclaveKeyNotVerified();
    error ExceedsAcceptableRange();
    error InvalidContractAddress();
    error CannotUseMatchingEngineRole();
    error InvalidEnclaveSignature(address invalidSignerAddress);
    error IncorrectImageId();
    error AttestationTimeout();
    error InvalidECIESACL();
    error BlacklistedImage(bytes32 imageId);
    error AlreadyABlacklistedImage(bytes32 imageId);
    error MustBeAnEnclave(bytes32 imageId);
    error FailedWhitelistingImages(bytes32 imageId);
    error FailedAddingToFamily(bytes32 imageId, bytes32 familyId);
    error InferredImageIdIsDifferent();
    error ImageAlreadyInFamily(bytes32 imageId, bytes32 familyId);

    // Prover-related Errors
    error ProverAlreadyExists();
    error InvalidProver();
    error InvalidProverCommission();
    error CannotLeaveWithActiveMarket();
    error AssignOnlyToIdleProvers();
    error InsufficientProverComputeAvailable();
    error OnlyWorkingProvers();
    error InvalidEnclaveKey();
    error OnlyValidProversCanRequestExit();
    error InvalidProverStatePerMarket();
    error UnstakeRequestNotInPlace();
    error ReduceComputeRequestNotInPlace();
    error MaxParallelRequestsPerMarketExceeded();
    error KeyAlreadyExists(address _address);
    error ReductionRequestNotValid();
    error PublicMarketsDontNeedKey();
    error CannotModifyImagesForPublicMarkets();

    // Market-related Errors
    error InvalidMarket();
    error AlreadyJoinedMarket();
    error CannotBeMoreThanDeclaredCompute();
    error CannotLeaveMarketWithActiveRequest();
    error MarketAlreadyExists();
    error InactiveMarket();
    error OnlyMarketCreator();
    error CannotRemoveDefaultImageFromMarket(uint256 marketId, bytes32 imageId);
    error NoRewardToClaim();

    // Task and Request Errors
    error CannotAssignExpiredTasks();
    error ExceedsMaximumMatchtime();
    error InvalidInputs();
    error ArityMismatch();
    error OnlyMatchingEngineCanAssign();
    error RequestAlreadyInPlace();
    error CannotSlashUsingValidInputs(uint256 bidId);

    // Proof and State Errors
    error ShouldBeInCreateState();
    error ProofPriceMismatch(uint256 bidId);
    error ProofTimeMismatch(uint256 bidId);
    error OnlyExpiredBidsCanBeCancelled(uint256 bidId);
    error OnlyAssignedBidsCanBeProved(uint256 bidId);
    error InvalidProof(uint256 bidId);
    error DeadlineNotCrossed(uint256 bidId);
    error ShouldBeInAssignedState(uint256 bidId);
    error OnlyProverCanDiscardRequest(uint256 bidId);

    // ProverManager
    error ZeroProverDataLength();
    error ZeroComputeToIncrease();
    error ZeroComputeToReduce();
    error ZeroRewardAddress();
    error ZeroDeclaredCompute();
    error ZeroNewRewardAddress();
    error ProverNotRegistered();
    
    // ProofMarketplace
    error InvalidProverRewardShare();
    error NotSlashableBidId(uint256 bidId);
    error InvalidProverProposedTime();
    error InvalidTimeForProofGeneration();
    
    // Staking
    error InsufficientStakeAmount();
    error NoStakeTokenAvailableToLock();
    error ZeroTokenAddress();
    error ZeroToAddress();

    // StakingManager
    error InvalidPool();
    error PoolAlreadyExists();
    error PoolDoesNotExist();
    error InvalidLength();
    error InvalidShares();
    error ZeroRewardShare();
    error PoolAlreadyEnabled();
    error PoolAlreadyDisabled();
    
    // Symbiotic Staking
    error InvalidSlashResultBlockRange();
    error EndBlockBeforeStartBlock();
    error NotRegisteredBlockNumber();
    error NotRegisteredTransmitter();
    error SubmissionAlreadyCompleted();
    error InvalidIndex();
    error InvalidNumOfTxs();
    error ZeroNumOfTxs();
    error InvalidCaptureTimestamp();
    error CooldownPeriodNotPassed();
    error NotIdxToSubmit();
    error ImageNotFound();
    error InvalidSignatureLength();
    error EnclaveKeyMismatch();
    error InvalidImage();
    error InvalidPublicKeyLength();
    error InvalidLastBlockNumber();
    error ImageAlreadyExists();
    error InvalidPCR0Length();
    error InvalidPCR1Length();
    error InvalidPCR2Length();
    error ZeroStakeTokenSelectionWeightSum();
    error NoStakeTokensAvailable();
    error TokenAlreadyExists();
    error TokenDoesNotExist();
    error InvalidComissionRate();
    error NoConfirmedTimestamp();

    // Native Staking
    error OnlyProverCanStake();
    error InsufficientStake();
    error InvalidIndexLength();
    error OnlyProverCanWithdrawStake();
    error WithdrawalTimeNotReached();
    error InvalidWithdrawalAmount();
    error TokenNotSupported();
    error InvalidWithdrawalDuration();
    error ZeroAmount();

    // SymbioticStakingReward
    error OnlyStakingManager();
    error ZeroProofMarketplaceAddress();
    error ZeroSymbioticStakingAddress();

    // Contract Address
    error InvalidAdmin();
    error InvalidFeeToken();
    error InvalidAttestationVerifier();
    error InvalidProofMarketplace();
    error InvalidProverManager();
    error InvalidSymbioticStaking();
    error InvalidStakingManager();
    error InvalidRewardDistributor();

    // TeeVerifierWrapper
    error TeeVerifierEnclaveKeyNotVerified(bytes PCR0, bytes PCR1, bytes PCR2);
}
