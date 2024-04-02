// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

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

    // Market-related Errors
    error InvalidMarket();
    error AlreadyJoinedMarket();
    error CannotBeMoreThanDeclaredCompute();
    error CannotLeaveMarketWithActiveRequest();
    error MarketAlreadyExists();
    error InactiveMarket();

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
}
