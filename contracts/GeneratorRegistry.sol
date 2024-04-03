// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20 as IERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20Upgradeable} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "./EntityKeyRegistry.sol";
import "./lib/Error.sol";
import "./ProofMarketplace.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _stakingToken, EntityKeyRegistry _entityRegistry) initializer {
        STAKING_TOKEN = _stakingToken;
        ENTITY_KEY_REGISTRY = _entityRegistry;
    }

    using HELPER for bytes;
    using HELPER for bytes32;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    bytes32 public constant PROOF_MARKET_PLACE_ROLE = keccak256("PROOF_MARKET_PLACE_ROLE");

    uint256 public constant PARALLEL_REQUESTS_UPPER_LIMIT = 100;
    uint256 public constant UNLOCK_WAIT_BLOCKS = 100;

    uint256 internal constant EXPONENT = 10 ** 18;
    uint256 internal constant REDUCTION_REQUEST_BLOCK_GAP = 1;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable STAKING_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => Generator) public generatorRegistry;
    mapping(address => mapping(uint256 => GeneratorInfoPerMarket)) public generatorInfoPerMarket;

    mapping(address => uint256) unstakeRequestBlock;
    mapping(address => uint256) reduceComputeRequestBlock;

    ProofMarketplace public proofMarketplace;

    enum GeneratorState {
        NULL,
        JOINED,
        NO_COMPUTE_AVAILABLE,
        WIP,
        REQUESTED_FOR_EXIT
    }

    struct Generator {
        address rewardAddress;
        uint256 totalStake;
        uint256 sumOfComputeAllocations;
        uint256 computeConsumed;
        uint256 stakeLocked;
        uint256 activeMarketplaces;
        uint256 declaredCompute;
        uint256 intendedStakeUtilization;
        uint256 intendedComputeUtilization;
        bytes generatorData;
    }

    struct GeneratorInfoPerMarket {
        GeneratorState state;
        uint256 computePerRequestRequired;
        uint256 proofGenerationCost;
        uint256 proposedTime;
        uint256 activeRequests;
    }

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Events end --------------------------------//

    event RegisteredGenerator(address indexed generator, uint256 initialCompute, uint256 initialStake);
    event DeregisteredGenerator(address indexed generator);

    event ChangedGeneratorRewardAddress(address indexed generator, address newRewardAddress);

    event JoinedMarketplace(address indexed generator, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketplace(address indexed generator, uint256 indexed marketId);
    event LeftMarketplace(address indexed generator, uint256 indexed marketId);

    event AddIvsKey(uint256 indexed marketId, address indexed signer);

    event AddedStake(address indexed generator, uint256 amount);
    event RequestStakeDecrease(address indexed generator, uint256 intendedUtilization);
    event RemovedStake(address indexed generator, uint256 amount);

    event IncreasedCompute(address indexed generator, uint256 compute);
    event RequestComputeDecrease(address indexed generator, uint256 intendedUtilization);
    event DecreaseCompute(address indexed generator, uint256 compute);

    //-------------------------------- Events end --------------------------------//

    function initialize(address _admin, address _proofMarketplace) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROOF_MARKET_PLACE_ROLE, _proofMarketplace);
        proofMarketplace = ProofMarketplace(_proofMarketplace);
    }

    /**
     * @notice Register Generator
     */
    function register(
        address rewardAddress,
        uint256 declaredCompute,
        uint256 initialStake,
        bytes memory generatorData
    ) external nonReentrant {
        address _generatorAddress = _msgSender();
        Generator memory generator = generatorRegistry[_generatorAddress];

        if (generatorData.length == 0 || rewardAddress == address(0) || declaredCompute == 0) {
            revert Error.CannotBeZero();
        }

        // prevents registering multiple times, unless deregistered
        if (generator.rewardAddress != address(0)) {
            revert Error.GeneratorAlreadyExists();
        }

        generatorRegistry[_generatorAddress] = Generator(
            rewardAddress,
            initialStake,
            0,
            0,
            0,
            0,
            declaredCompute,
            EXPONENT,
            EXPONENT,
            generatorData
        );

        // optional to stake during registration itself
        if (initialStake != 0) {
            STAKING_TOKEN.safeTransferFrom(_generatorAddress, address(this), initialStake);
        }
        emit RegisteredGenerator(_generatorAddress, declaredCompute, initialStake);
    }

    /**
     * @notice Change Generator's reward address
     */
    function changeRewardAddress(address newRewardAddress) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];
        if (newRewardAddress == address(0) || generator.rewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        generator.rewardAddress = newRewardAddress;

        emit ChangedGeneratorRewardAddress(_generatorAddress, newRewardAddress);
    }

    /**
     * @notice Increase generator's compute
     */
    function increaseDeclaredCompute(uint256 computeToIncrease) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        if (generator.rewardAddress == address(0) || generator.generatorData.length == 0) {
            revert Error.CannotBeZero();
        }

        generator.declaredCompute += computeToIncrease;

        emit IncreasedCompute(_generatorAddress, computeToIncrease);
    }

    /**
     * @notice Notify matching engine about compute reduction. This will stop matching engine from assigning new tasks till the compute is down
     * @param newUtilization New Utilization is in percentage scaled up to 10e18
     */
    function intendToReduceCompute(uint256 newUtilization) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        if (generator.rewardAddress == address(0) || generator.generatorData.length == 0) {
            revert Error.CannotBeZero();
        }

        // if request is already in place, this will ICU will be less than EXP (as per design)
        if (generator.intendedComputeUtilization != EXPONENT) {
            revert Error.RequestAlreadyInPlace();
        }

        // new utilization should be always less than EXP
        if (newUtilization >= EXPONENT) {
            revert Error.ExceedsAcceptableRange();
        }

        // new utilization after update
        uint256 newTotalCompute = (newUtilization * generator.declaredCompute) / EXPONENT;

        // this is min compute requires for atleast 1 request from each supported market
        if (newTotalCompute <= generator.sumOfComputeAllocations) {
            revert Error.ExceedsAcceptableRange();
        }

        // ensures that new utilization is not too small to release and prevent generator dead lock
        // uint256 computeToRelease = generator.declaredCompute - newTotalCompute;
        if (generator.declaredCompute - newTotalCompute == 0) {
            revert Error.CannotBeZero();
        }

        // temporary value to store the new utilization
        generator.intendedComputeUtilization = newUtilization;

        // block number after which this intent which execute
        reduceComputeRequestBlock[_generatorAddress] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestComputeDecrease(_generatorAddress, newUtilization);
    }

    /**
     * @notice Free up the unused compute. intendToReduceCompute must have been called before this function
     */
    function decreaseDeclaredCompute() external {
        address generatorAddress = _msgSender();

        Generator storage generator = generatorRegistry[generatorAddress];

        if (generator.generatorData.length == 0 || generator.rewardAddress == address(0)) {
            revert Error.InvalidGenerator();
        }

        if (generator.intendedComputeUtilization == EXPONENT) {
            revert Error.ReduceComputeRequestNotInPlace();
        }

        uint256 newTotalCompute = (generator.intendedComputeUtilization * generator.declaredCompute) / EXPONENT;
        uint256 computeToRelease = generator.declaredCompute - newTotalCompute;

        if (newTotalCompute < generator.computeConsumed) {
            revert Error.InsufficientGeneratorComputeAvailable();
        }

        if (newTotalCompute < generator.sumOfComputeAllocations) {
            revert Error.InsufficientGeneratorComputeAvailable();
        }

        generator.declaredCompute = newTotalCompute;
        generator.intendedComputeUtilization = EXPONENT;

        if (
            !(block.number >= reduceComputeRequestBlock[generatorAddress] &&
                reduceComputeRequestBlock[generatorAddress] != 0)
        ) {
            revert Error.ReductionRequestNotValid();
        }

        delete reduceComputeRequestBlock[generatorAddress];
        emit DecreaseCompute(generatorAddress, computeToRelease);
    }

    /**
     * @notice Add/Increase stake
     */
    function stake(address generatorAddress, uint256 amount) external nonReentrant returns (uint256) {
        Generator storage generator = generatorRegistry[generatorAddress];
        if (generator.generatorData.length == 0 || generator.rewardAddress == address(0)) {
            revert Error.InvalidGenerator();
        }

        if (amount == 0) {
            revert Error.CannotBeZero();
        }

        STAKING_TOKEN.safeTransferFrom(_msgSender(), address(this), amount);
        generator.totalStake += amount;

        emit AddedStake(generatorAddress, amount);
        return generator.totalStake;
    }

    /**
     * @notice Notify matching engine about stake reduction. This will stop matching engine from assigning new tasks till the locked stake is down
     * @param newUtilization New Utilization is in percentage scaled up to 10e18
     */
    function intendToReduceStake(uint256 newUtilization) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        if (generator.rewardAddress == address(0) || generator.generatorData.length == 0) {
            revert Error.CannotBeZero();
        }

        // if request is already in place, this will ICU will be less than EXP (as per design)
        if (generator.intendedComputeUtilization != EXPONENT) {
            revert Error.RequestAlreadyInPlace();
        }

        // new utilization should be always less than EXP
        if (newUtilization >= EXPONENT) {
            revert Error.ExceedsAcceptableRange();
        }

        generator.intendedStakeUtilization = newUtilization;

        // new utilization after update
        uint256 newTotalStake = (newUtilization * generator.totalStake) / EXPONENT;

        // ensures that new utilization is not too small to release and prevent generator dead lock
        // uint256 stakeToRelease = generator.totalStake - newTotalStake;
        if (generator.totalStake - newTotalStake == 0) {
            revert Error.CannotBeZero();
        }

        unstakeRequestBlock[_generatorAddress] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestStakeDecrease(_generatorAddress, newUtilization);
    }

    /**
     * @notice Free up the unused stake. intendToReduceStake must have been called before this function
     */
    function unstake(address to) external nonReentrant {
        address generatorAddress = _msgSender();

        Generator storage generator = generatorRegistry[generatorAddress];
        if (generator.generatorData.length == 0 || generator.rewardAddress == address(0)) {
            revert Error.InvalidGenerator();
        }

        if (generator.intendedStakeUtilization == EXPONENT) {
            revert Error.UnstakeRequestNotInPlace();
        }

        uint256 newTotalStake = (generator.intendedStakeUtilization * generator.totalStake) / EXPONENT;

        uint256 amountToTransfer = generator.totalStake - newTotalStake;

        // prevent removing amount unless existing stake is not released
        if (newTotalStake < generator.stakeLocked) {
            revert Error.InsufficientStakeToLock();
        }

        // amountToTransfer will be non-zero
        STAKING_TOKEN.safeTransfer(to, amountToTransfer);

        generator.totalStake = newTotalStake;
        generator.intendedStakeUtilization = EXPONENT;

        if (!(block.number >= unstakeRequestBlock[generatorAddress] && unstakeRequestBlock[generatorAddress] != 0)) {
            revert Error.ReductionRequestNotValid();
        }

        delete unstakeRequestBlock[generatorAddress];
        emit RemovedStake(generatorAddress, amountToTransfer);
    }

    /**
     * @notice Deregister the generator
     */
    function deregister(address refundAddress) external nonReentrant {
        address _generatorAddress = _msgSender();
        Generator memory generator = generatorRegistry[_generatorAddress];

        if (generator.sumOfComputeAllocations != 0) {
            revert Error.CannotLeaveWithActiveMarket();
        }

        STAKING_TOKEN.safeTransfer(refundAddress, generator.totalStake);
        delete generatorRegistry[_generatorAddress];

        emit DeregisteredGenerator(_generatorAddress);
    }

    /**
     * @notice update the encryption key
     */
    function updateEncryptionKey(
        uint256 marketId,
        bytes memory attestationData,
        bytes calldata enclaveSignature
    ) external {
        address generatorAddress = _msgSender();
        Generator memory generator = generatorRegistry[generatorAddress];

        (, bytes32 expectedImageId, , , , ) = proofMarketplace.marketData(marketId);

        if (!(expectedImageId != bytes32(0) || expectedImageId != HELPER.NO_ENCLAVE_ID)) {
            revert Error.PublicMarketsDontNeedKey();
        }

        if (expectedImageId != attestationData.GET_IMAGE_ID_FROM_ATTESTATION()) {
            revert Error.IncorrectImageId();
        }

        // just an extra check to prevent spam
        if (generator.rewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        bytes memory pubkey = attestationData.GET_PUBKEY();

        // confirms that _msgSender() has access to enclave
        attestationData.VERIFY_ENCLAVE_SIGNATURE(enclaveSignature, _msgSender());

        // don't whitelist, because same imageId must be used to update the key
        ENTITY_KEY_REGISTRY.updatePubkey(generatorAddress, marketId, pubkey, attestationData);
    }

    /**
     * @notice Add IVS key for a given market
     */
    function addIvsKey(uint256 marketId, bytes memory attestationData, bytes calldata enclaveSignature) external {
        (, , , , bytes32 expectedIvsImageId, ) = proofMarketplace.marketData(marketId);

        // ensure only right image is used
        if (expectedIvsImageId != attestationData.GET_IMAGE_ID_FROM_ATTESTATION()) {
            revert Error.IncorrectImageId();
        }

        // confirms that _msgSender() has access to enclave
        attestationData.VERIFY_ENCLAVE_SIGNATURE(enclaveSignature, _msgSender());

        // only whitelist key, after verifying the attestation
        ENTITY_KEY_REGISTRY.verifyKey(attestationData);
        emit AddIvsKey(marketId, attestationData.GET_ADDRESS());
    }

    /**
     * @notice Remove generator's encryption key
     */
    function removeEncryptionKey(uint256 marketId) external {
        // generatorAddress = _msgSender();
        ENTITY_KEY_REGISTRY.removePubkey(_msgSender(), marketId);
    }

    function joinMarketplace(
        uint256 marketId,
        uint256 computePerRequestRequired,
        uint256 proofGenerationCost,
        uint256 proposedTime,
        bool updateMarketDedicatedKey, // false if not a private market
        bytes memory attestationData, // verification ignored if updateMarketDedicatedKey==false
        bytes calldata enclaveSignature // ignored if updateMarketDedicatedKey==false
    ) external {
        address generatorAddress = _msgSender();

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        // proof generation time can't be zero.
        // compute required per proof can't be zero
        if (generator.rewardAddress == address(0) || proposedTime == 0 || computePerRequestRequired == 0) {
            revert Error.CannotBeZero();
        }

        (address marketVerifierContractAddress, bytes32 expectedImageId) = _readMarketData(marketId);

        // prevent joining invalid market
        if (marketVerifierContractAddress == address(0)) {
            revert Error.InvalidMarket();
        }

        // prevents re-joining
        if (info.state != GeneratorState.NULL) {
            revert Error.AlreadyJoinedMarket();
        }

        // sum of compute allocation of all supported markets
        generator.sumOfComputeAllocations += computePerRequestRequired;

        // ensures that generator will support atleast 1 request for every market
        if (generator.sumOfComputeAllocations > generator.declaredCompute) {
            revert Error.CannotBeMoreThanDeclaredCompute();
        }

        // increment the number of active market places supported
        generator.activeMarketplaces++;

        // update market specific info for the generator
        generatorInfoPerMarket[generatorAddress][marketId] = GeneratorInfoPerMarket(
            GeneratorState.JOINED,
            computePerRequestRequired,
            proofGenerationCost,
            proposedTime,
            0
        );

        // if prover is public, no need to check the enclave signatures
        if (expectedImageId != bytes32(0) && expectedImageId != HELPER.NO_ENCLAVE_ID) {
            // check the image
            if (expectedImageId != attestationData.GET_IMAGE_ID_FROM_ATTESTATION()) {
                revert Error.IncorrectImageId();
            }

            // if users decides to update the market key in the same transaction
            if (updateMarketDedicatedKey) {
                // confirms that generatorAddress has access to enclave
                attestationData.VERIFY_ENCLAVE_SIGNATURE(enclaveSignature, generatorAddress);

                // whitelist every image here because it is verified by the generator
                ENTITY_KEY_REGISTRY.updatePubkey(
                    generatorAddress,
                    marketId,
                    attestationData.GET_PUBKEY(),
                    attestationData
                );
            }
        }
        emit JoinedMarketplace(generatorAddress, marketId, computePerRequestRequired);
    }

    function _readMarketData(uint256 marketId) internal view returns (address, bytes32) {
        (IVerifier _verifier, bytes32 expectedImageId, , , , ) = proofMarketplace.marketData(marketId);

        return (address(_verifier), expectedImageId);
    }

    function getGeneratorState(
        address generatorAddress,
        uint256 marketId
    ) public view returns (GeneratorState, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        Generator memory generator = generatorRegistry[generatorAddress];

        if (info.state == GeneratorState.NULL) {
            return (GeneratorState.NULL, 0);
        }

        if (info.state == GeneratorState.REQUESTED_FOR_EXIT) {
            return (GeneratorState.REQUESTED_FOR_EXIT, 0);
        }

        uint256 idleCapacity = _maxReducableCompute(generatorAddress);

        if (info.state != GeneratorState.NULL && idleCapacity == 0) {
            return (GeneratorState.NO_COMPUTE_AVAILABLE, 0);
        }

        if (idleCapacity == generator.declaredCompute) {
            return (GeneratorState.JOINED, idleCapacity);
        }

        if (idleCapacity != 0 && idleCapacity < generator.declaredCompute) {
            return (GeneratorState.WIP, idleCapacity);
        }
        return (GeneratorState.NULL, 0);
    }

    function _maxReducableCompute(address generatorAddress) internal view returns (uint256) {
        Generator memory generator = generatorRegistry[generatorAddress];

        uint256 maxUsableCompute = (generator.declaredCompute * generator.intendedComputeUtilization) / EXPONENT;

        if (maxUsableCompute < generator.computeConsumed) {
            return 0;
        }

        return maxUsableCompute - generator.computeConsumed;
    }

    function _maxReducableStake(address generatorAddress) internal view returns (uint256) {
        Generator memory generator = generatorRegistry[generatorAddress];

        uint256 maxUsableStake = (generator.totalStake * generator.intendedStakeUtilization) / EXPONENT;
        if (maxUsableStake < generator.stakeLocked) {
            return 0;
        }

        return maxUsableStake - generator.stakeLocked;
    }

    function leaveMarketplaces(uint256[] calldata marketIds) external {
        for (uint256 index = 0; index < marketIds.length; index++) {
            // generatorAddress = _msgSender();
            _leaveMarketplace(_msgSender(), marketIds[index]);
        }
    }

    function leaveMarketplace(uint256 marketId) external {
        // generatorAddress = _msgSender();
        _leaveMarketplace(_msgSender(), marketId);
    }

    function requestForExitMarketplaces(uint256[] calldata marketIds) external {
        for (uint256 index = 0; index < marketIds.length; index++) {
            // generatorAddress = _msgSender();
            _requestForExitMarketplace(_msgSender(), marketIds[index]);
        }
    }

    function requestForExitMarketplace(uint256 marketId) external {
        // generatorAddress = _msgSender();
        _requestForExitMarketplace(_msgSender(), marketId);
    }

    function _requestForExitMarketplace(address generatorAddress, uint256 marketId) internal {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);

        // only valid generators can exit the market
        if (!(state != GeneratorState.NULL && state != GeneratorState.REQUESTED_FOR_EXIT)) {
            revert Error.OnlyValidGeneratorsCanRequestExit();
        }
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        info.state = GeneratorState.REQUESTED_FOR_EXIT;

        // alerts matching engine to stop assinging the requests of given market
        emit RequestExitMarketplace(generatorAddress, marketId);

        // if there are no active requests, proceed to leave market plaes
        if (info.activeRequests == 0) {
            _leaveMarketplace(generatorAddress, marketId);
        }
    }

    function _leaveMarketplace(address generatorAddress, uint256 marketId) internal {
        (IVerifier marketVerifier, , , , , ) = proofMarketplace.marketData(marketId);

        // check if market is valid
        if (address(marketVerifier) == address(0)) {
            revert Error.InvalidMarket();
        }

        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        if (info.state == GeneratorState.NULL) {
            revert Error.InvalidGeneratorStatePerMarket();
        }

        // check if there are any active requestsw
        if (info.activeRequests != 0) {
            revert Error.CannotLeaveMarketWithActiveRequest();
        }

        Generator storage generator = generatorRegistry[generatorAddress];

        generator.sumOfComputeAllocations -= info.computePerRequestRequired;
        generator.activeMarketplaces -= 1;

        delete generatorInfoPerMarket[generatorAddress][marketId];
        emit LeftMarketplace(generatorAddress, marketId);
    }

    /**
     * @notice Should be called by proof market place only, PMP is assigned SLASHER_ROLE
     */
    function slashGenerator(
        address generatorAddress,
        uint256 marketId,
        uint256 slashingAmount,
        address rewardAddress
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) returns (uint256) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);

        // other generator states can't be slashed
        if (
            !(state == GeneratorState.WIP ||
                state == GeneratorState.REQUESTED_FOR_EXIT ||
                state == GeneratorState.NO_COMPUTE_AVAILABLE)
        ) {
            revert Error.CannotBeSlashed();
        }

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        info.activeRequests--;

        generator.totalStake -= slashingAmount;
        generator.stakeLocked -= slashingAmount;

        generator.computeConsumed -= info.computePerRequestRequired;

        STAKING_TOKEN.safeTransfer(rewardAddress, slashingAmount);

        return generator.totalStake;
    }

    function assignGeneratorTask(
        address generatorAddress,
        uint256 marketId,
        uint256 stakeToLock
    ) external nonReentrant onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (GeneratorState state, uint256 idleCapacity) = getGeneratorState(generatorAddress, marketId);

        if (!(state == GeneratorState.JOINED || state == GeneratorState.WIP)) {
            revert Error.AssignOnlyToIdleGenerators();
        }

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        // requiredCompute <= idleCapacity
        if (info.computePerRequestRequired > idleCapacity) {
            revert Error.InsufficientGeneratorComputeAvailable();
        }
        if (info.activeRequests > PARALLEL_REQUESTS_UPPER_LIMIT) {
            revert Error.MaxParallelRequestsPerMarketExceeded();
        }

        uint256 availableStake = _maxReducableStake(generatorAddress);
        if (availableStake < stakeToLock) {
            revert Error.InsufficientStakeToLock();
        }

        generator.stakeLocked += stakeToLock;
        generator.computeConsumed += info.computePerRequestRequired;
        info.activeRequests++;
    }

    function completeGeneratorTask(
        address generatorAddress,
        uint256 marketId,
        uint256 stakeToRelease
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);
        if (
            !(state == GeneratorState.WIP ||
                state == GeneratorState.REQUESTED_FOR_EXIT ||
                state == GeneratorState.NO_COMPUTE_AVAILABLE)
        ) {
            revert Error.OnlyWorkingGenerators();
        }

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        uint256 computeReleased = info.computePerRequestRequired;
        generator.computeConsumed -= computeReleased;

        generator.stakeLocked -= stakeToRelease;
        info.activeRequests--;
    }

    function getGeneratorAssignmentDetails(
        address generatorAddress,
        uint256 marketId
    ) public view returns (uint256, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        return (info.proofGenerationCost, info.proposedTime);
    }

    function getGeneratorRewardDetails(
        address generatorAddress,
        uint256 marketId
    ) public view returns (address, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        Generator memory generator = generatorRegistry[generatorAddress];

        return (generator.rewardAddress, info.proofGenerationCost);
    }

    // for further increase
    uint256[50] private __gap1_0;
}
