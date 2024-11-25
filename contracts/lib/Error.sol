// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

    // Task and Request Errors
    error CannotAssignExpiredTasks();
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
    error ShouldBeInCrossedDeadlineState(uint256 bidId);
    error ShouldBeInAssignedState(uint256 bidId);
    error OnlyProverCanDiscardRequest(uint256 bidId);
}
