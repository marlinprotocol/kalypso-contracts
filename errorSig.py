from web3 import Web3

errors = [
    "OnlyAdminCanCall()",
    "CannotBeAdminLess()",
    "CannotBeZero()",
    "CannotBeSlashed()",
    "InsufficientStakeToLock()",
    "EnclaveKeyNotVerified()",
    "ExceedsAcceptableRange()",
    "InvalidContractAddress()",
    "CannotUseMatchingEngineRole()",
    "InvalidEnclaveSignature(address)",
    "IncorrectImageId()",
    "AttestationTimeout()",
    "InvalidECIESACL()",
    "BlacklistedImage(bytes32)",
    "AlreadyABlacklistedImage(bytes32)",
    "MustBeAnEnclave(bytes32)",
    "FailedWhitelistingImages(bytes32)",
    "FailedAddingToFamily(bytes32,bytes32)",
    "InferredImageIdIsDifferent()",
    "ImageAlreadyInFamily(bytes32,bytes32)",
    "GeneratorAlreadyExists()",
    "InvalidGenerator()",
    "CannotLeaveWithActiveMarket()",
    "AssignOnlyToIdleGenerators()",
    "InsufficientGeneratorComputeAvailable()",
    "OnlyWorkingGenerators()",
    "InvalidEnclaveKey()",
    "OnlyValidGeneratorsCanRequestExit()",
    "InvalidGeneratorStatePerMarket()",
    "UnstakeRequestNotInPlace()",
    "ReduceComputeRequestNotInPlace()",
    "MaxParallelRequestsPerMarketExceeded()",
    "KeyAlreadyExists(address)",
    "ReductionRequestNotValid()",
    "PublicMarketsDontNeedKey()",
    "CannotModifyImagesForPublicMarkets()",
    "InvalidMarket()",
    "AlreadyJoinedMarket()",
    "CannotBeMoreThanDeclaredCompute()",
    "CannotLeaveMarketWithActiveRequest()",
    "MarketAlreadyExists()",
    "InactiveMarket()",
    "OnlyMarketCreator()",
    "CannotRemoveDefaultImageFromMarket(uint256,bytes32)",
    "CannotAssignExpiredTasks()",
    "InvalidInputs()",
    "ArityMismatch()",
    "OnlyMatchingEngineCanAssign()",
    "RequestAlreadyInPlace()",
    "CannotSlashUsingValidInputs(uint256)",
    "ShouldBeInCreateState()",
    "ProofPriceMismatch(uint256)",
    "ProofTimeMismatch(uint256)",
    "OnlyExpiredAsksCanBeCancelled(uint256)",
    "OnlyAssignedAsksCanBeProved(uint256)",
    "InvalidProof(uint256)",
    "ShouldBeInCrossedDeadlineState(uint256)",
    "ShouldBeInAssignedState(uint256)",
    "OnlyGeneratorCanDiscardRequest(uint256)"
]

# Calculate the hash for each error signature and get the first 4 bytes
for error in errors:
    error_hash = Web3.keccak(text=error).hex()
    error_selector = error_hash[:10]
    print(f"{error}: {error_selector}")
