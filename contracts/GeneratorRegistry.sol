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
import {IStakingManager} from "./interfaces/staking/IStakingManager.sol";
import "./interfaces/IGeneratorRegistry.sol";

import "./interfaces/IGeneratorCallbacks.sol";
import "./staking/l2_contracts/StakingManager.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IGeneratorRegistry,
    IGeneratorCallbacks
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EntityKeyRegistry _entityRegistry, StakingManager _stakingManager) initializer {
        ENTITY_KEY_REGISTRY = _entityRegistry;
        STAKING_MANAGER = _stakingManager;
    }

    using HELPER for bytes;
    using HELPER for bytes32;
    using HELPER for uint256;

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
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    StakingManager public immutable STAKING_MANAGER;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => Generator) public generatorRegistry;
    mapping(address => mapping(uint256 => GeneratorInfoPerMarket)) public generatorInfoPerMarket;

    mapping(address => uint256) reduceComputeRequestBlock;

    ProofMarketplace public proofMarketplace;

    address public stakingManager;

    enum GeneratorState {
        NULL,
        JOINED,
        NO_COMPUTE_AVAILABLE,
        WIP,
        REQUESTED_FOR_EXIT
    }

    struct Generator {
        address rewardAddress;
        uint256 sumOfComputeAllocations;
        uint256 computeConsumed;
        uint256 activeMarketplaces;
        uint256 declaredCompute;
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

    function initialize(address _admin, address _proofMarketplace, address _stakingManager) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROOF_MARKET_PLACE_ROLE, _proofMarketplace);
        proofMarketplace = ProofMarketplace(_proofMarketplace);
        stakingManager = _stakingManager;
    }

    /**
     * @notice Register Generator
     */
    function register(
        address rewardAddress,
        uint256 declaredCompute,
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
            0,
            0,
            0,
            declaredCompute,
            EXPONENT,
            generatorData
        );

        emit RegisteredGenerator(_generatorAddress, declaredCompute);
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
     * @param computeToReduce Compute To Reduce
     */
    function intendToReduceCompute(uint256 computeToReduce) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        if (generator.rewardAddress == address(0) || generator.generatorData.length == 0 || computeToReduce == 0) {
            revert Error.CannotBeZero();
        }

        // if request is already in place, this will ICU will be less than EXP (as per design)
        if (generator.intendedComputeUtilization != EXPONENT) {
            revert Error.RequestAlreadyInPlace();
        }

        // new utilization after update
        uint256 newTotalCompute = generator.declaredCompute - computeToReduce;

        // this is min compute requires for atleast 1 request from each supported market
        if (newTotalCompute <= generator.sumOfComputeAllocations) {
            revert Error.ExceedsAcceptableRange();
        }

        uint256 newUtilization = (newTotalCompute * EXPONENT) / generator.declaredCompute;
        // new utilization should be always less than EXP
        if (newUtilization >= EXPONENT) {
            revert Error.ExceedsAcceptableRange();
        }

        // temporary value to store the new utilization
        generator.intendedComputeUtilization = newUtilization;

        // block number after which this intent which execute
        reduceComputeRequestBlock[_generatorAddress] = HELPER.blockNumber() + REDUCTION_REQUEST_BLOCK_GAP;
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

        if (!(HELPER.blockNumber() >= reduceComputeRequestBlock[generatorAddress] && reduceComputeRequestBlock[generatorAddress] != 0)) {
            revert Error.ReductionRequestNotValid();
        }

        delete reduceComputeRequestBlock[generatorAddress];
        emit DecreaseCompute(generatorAddress, computeToRelease);
    }

    /**
     * @notice Deregister the generator
     */
    function deregister() external nonReentrant {
        address _generatorAddress = _msgSender();
        Generator memory generator = generatorRegistry[_generatorAddress];

        if (generator.sumOfComputeAllocations != 0) {
            revert Error.CannotLeaveWithActiveMarket();
        }

        delete generatorRegistry[_generatorAddress];

        emit DeregisteredGenerator(_generatorAddress);
    }

    /**
     * @notice update the encryption key
     */
    function updateEncryptionKey(uint256 marketId, bytes memory attestationData, bytes calldata enclaveSignature) external {
        // generator here is _msgSender()
        _updateEncryptionKey(_msgSender(), marketId, attestationData, enclaveSignature);
    }


    function _updateEncryptionKey(
        address generatorAddress,
        uint256 marketId,
        bytes memory attestationData,
        bytes calldata enclaveSignature
    ) internal {
        Generator memory generator = generatorRegistry[generatorAddress];

        // just an extra check to prevent spam
        if (generator.rewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        // only for knowing if the given market is private or public
        (, bytes32 generatorImageId) = _readMarketData(marketId);
        if (!generatorImageId.IS_ENCLAVE()) {
            revert Error.PublicMarketsDontNeedKey();
        }

        if (!ENTITY_KEY_REGISTRY.isImageInFamily(attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), marketId.GENERATOR_FAMILY_ID())) {
            revert Error.IncorrectImageId();
        }

        bytes memory pubkey = attestationData.GET_PUBKEY();

        attestationData.VERIFY_ENCLAVE_SIGNATURE(enclaveSignature, generatorAddress);

        // don't whitelist, because same imageId must be used to update the key
        ENTITY_KEY_REGISTRY.updatePubkey(generatorAddress, marketId, pubkey, attestationData);
    }

    /**
     * @notice Add IVS key for a given market
     */
    function addIvsKey(uint256 marketId, bytes memory attestationData, bytes calldata enclaveSignature) external {
        // ensure only right image is used
        if (!ENTITY_KEY_REGISTRY.isImageInFamily(attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), marketId.IVS_FAMILY_ID())) {
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

        // only for checking if any market id valid or not
        (address marketVerifierContractAddress, ) = _readMarketData(marketId);
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

        if (updateMarketDedicatedKey) {
            _updateEncryptionKey(generatorAddress, marketId, attestationData, enclaveSignature);
        }
        emit JoinedMarketplace(generatorAddress, marketId, computePerRequestRequired);
    }

    function _readMarketData(uint256 marketId) internal view returns (address, bytes32) {
        (IVerifier _verifier, bytes32 generatorImageId, , , , , ) = proofMarketplace.marketData(marketId);

        return (address(_verifier), generatorImageId);
    }

    function getGeneratorState(address generatorAddress, uint256 marketId) public view returns (GeneratorState, uint256) {
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
        (IVerifier marketVerifier, , , , , , ) = proofMarketplace.marketData(marketId);

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
     * @notice Should be called by proof market place only, PMP is assigned SLASHER_ROLE, called when generators is about to be slashed
     */
    function releaseGeneratorResources(
        address generatorAddress,
        uint256 marketId
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);

        // All states = NULL,JOINED,NO_COMPUTE_AVAILABLE,WIP,REQUESTED_FOR_EXIT
        // only generators in WIP, REQUESTED_FOR_EXIT, NO_COMPUTE_AVAILABLE can submit the request, NULL and JOINED can't
        if (state == GeneratorState.NULL || state == GeneratorState.JOINED) {
            revert Error.CannotBeSlashed();
        }

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        info.activeRequests--;

        generator.computeConsumed -= info.computePerRequestRequired;
        emit ComputeLockReleased(generatorAddress, info.computePerRequestRequired);
    }

    function assignGeneratorTask(
        uint256 askId,
        address generatorAddress,
        uint256 marketId
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

        uint256 computeConsumed = info.computePerRequestRequired;
        generator.computeConsumed += computeConsumed;

        IStakingManager(stakingManager).onJobCreation(askId, generatorAddress);

        emit ComputeLockImposed(generatorAddress, computeConsumed);
        info.activeRequests++;
    }

    function completeGeneratorTask(
        uint256 askId,
        address generatorAddress,
        uint256 marketId,
        uint256 stakeToRelease
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);

        // All states = NULL,JOINED,NO_COMPUTE_AVAILABLE,WIP,REQUESTED_FOR_EXIT
        // only generators in WIP, REQUESTED_FOR_EXIT, NO_COMPUTE_AVAILABLE can submit the request, NULL and JOINED can't
        if (state == GeneratorState.NULL || state == GeneratorState.JOINED) {
            revert Error.OnlyWorkingGenerators();
        }

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        uint256 computeReleased = info.computePerRequestRequired;
        generator.computeConsumed -= computeReleased;

        IStakingManager(stakingManager).onJobCompletion(askId, generatorAddress, stakeToRelease);

        emit ComputeLockReleased(generatorAddress, computeReleased);

        info.activeRequests--;
    }

    function getGeneratorAssignmentDetails(address generatorAddress, uint256 marketId) public view returns (uint256, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        return (info.proofGenerationCost, info.proposedTime);
    }

    function getGeneratorRewardDetails(address generatorAddress, uint256 marketId) public view returns (address, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        Generator memory generator = generatorRegistry[generatorAddress];

        return (generator.rewardAddress, info.proofGenerationCost);
    }

    function addStakeCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit AddedStake(generatorAddress, token, amount);
    }

    function intendToReduceStakeCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit IntendToReduceStake(generatorAddress, token, amount);
    }
    
    function removeStakeCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit RemovedStake(generatorAddress, token, amount);
    }

    function stakeLockImposedCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeLockImposed(generatorAddress, token, amount);
    }

    function stakeLockReleasedCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeLockReleased(generatorAddress, token, amount);
    }

    function stakeSlashedCallback(address generatorAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeSlashed(generatorAddress, token, amount);
    }

    function symbioticCompleteSnapshotCallback(uint256 captureTimestamp) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit SymbioticCompleteSnapshot(captureTimestamp);
    }

    // for further increase
    uint256[50] private __gap1_0;
}
