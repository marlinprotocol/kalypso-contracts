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

    // Generator-related Errors
    error GeneratorAlreadyExists();
    error InvalidGenerator();
    error CannotLeaveWithActiveMarket();
    error AssignOnlyToIdleGenerators();
    error InsufficientGeneratorComputeAvailable();
    error OnlyWorkingGenerators();
    error InvalidEnclaveKey();
    error OnlyValidGeneratorsCanRequestExit();
    error InvalidGeneratorStatePerMarket();
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
    error CannotSlashUsingValidInputs(uint256 askId);

    // Proof and State Errors
    error ShouldBeInCreateState();
    error ProofPriceMismatch(uint256 askId);
    error ProofTimeMismatch(uint256 askId);
    error OnlyExpiredAsksCanBeCancelled(uint256 askId);
    error OnlyAssignedAsksCanBeProved(uint256 askId);
    error InvalidProof(uint256 askId);
    error ShouldBeInCrossedDeadlineState(uint256 askId);
    error ShouldBeInAssignedState(uint256 askId);
    error OnlyGeneratorCanDiscardRequest(uint256 askId);

    // Tee Verifier Errors
    error TeeVerifierEnclaveKeyNotVerified(bytes PCR0, bytes PCR1, bytes PCR2);
}
