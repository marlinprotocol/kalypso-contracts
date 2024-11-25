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
import {IVerifier} from "./interfaces/IVerifier.sol";
import "./interfaces/IProverRegistry.sol";

import "./interfaces/IProverCallbacks.sol";
import "./staking/l2_contracts/StakingManager.sol";

contract ProverRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IProverRegistry,
    IProverCallbacks
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
    mapping(address => Prover) public proverRegistry;
    mapping(address => mapping(uint256 => ProverInfoPerMarket)) public proverInfoPerMarket;

    mapping(address => uint256) reduceComputeRequestBlock;

    ProofMarketplace public proofMarketplace;

    address public stakingManager;

    enum ProverState {
        NULL,
        JOINED,
        NO_COMPUTE_AVAILABLE,
        WIP,
        REQUESTED_FOR_EXIT
    }

    struct Prover {
        address rewardAddress;
        uint256 sumOfComputeAllocations;
        uint256 computeConsumed;
        uint256 activeMarketplaces;
        uint256 declaredCompute;
        uint256 intendedComputeUtilization;
        bytes proverData;
    }

    struct ProverInfoPerMarket {
        ProverState state;
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
     * @notice Register Prover
     */
    function register(
        address rewardAddress,
        uint256 declaredCompute,
        bytes memory proverData
    ) external nonReentrant {
        address _proverAddress = _msgSender();
        Prover memory prover = proverRegistry[_proverAddress];

        if (proverData.length == 0 || rewardAddress == address(0) || declaredCompute == 0) {
            revert Error.CannotBeZero();
        }

        // prevents registering multiple times, unless deregistered
        if (prover.rewardAddress != address(0)) {
            revert Error.ProverAlreadyExists();
        }

        proverRegistry[_proverAddress] = Prover(
            rewardAddress,
            0,
            0,
            0,
            declaredCompute,
            EXPONENT,
            proverData
        );

        emit RegisteredProver(_proverAddress, declaredCompute);
    }

    /**
     * @notice Change Prover's reward address
     */
    function changeRewardAddress(address newRewardAddress) external {
        address _proverAddress = _msgSender();
        Prover storage prover = proverRegistry[_proverAddress];
        if (newRewardAddress == address(0) || prover.rewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        prover.rewardAddress = newRewardAddress;

        emit ChangedProverRewardAddress(_proverAddress, newRewardAddress);
    }

    /**
     * @notice Increase prover's compute
     */
    function increaseDeclaredCompute(uint256 computeToIncrease) external {
        address _proverAddress = _msgSender();
        Prover storage prover = proverRegistry[_proverAddress];

        if (prover.rewardAddress == address(0) || prover.proverData.length == 0) {
            revert Error.CannotBeZero();
        }

        prover.declaredCompute += computeToIncrease;

        emit IncreasedCompute(_proverAddress, computeToIncrease);
    }

    /**
     * @notice Notify matching engine about compute reduction. This will stop matching engine from assigning new tasks till the compute is down
     * @param computeToReduce Compute To Reduce
     */
    function intendToReduceCompute(uint256 computeToReduce) external {
        address _proverAddress = _msgSender();
        Prover storage prover = proverRegistry[_proverAddress];

        if (prover.rewardAddress == address(0) || prover.proverData.length == 0 || computeToReduce == 0) {
            revert Error.CannotBeZero();
        }

        // if request is already in place, this will ICU will be less than EXP (as per design)
        if (prover.intendedComputeUtilization != EXPONENT) {
            revert Error.RequestAlreadyInPlace();
        }

        // new utilization after update
        uint256 newTotalCompute = prover.declaredCompute - computeToReduce;

        // this is min compute requires for atleast 1 request from each supported market
        if (newTotalCompute <= prover.sumOfComputeAllocations) {
            revert Error.ExceedsAcceptableRange();
        }

        uint256 newUtilization = (newTotalCompute * EXPONENT) / prover.declaredCompute;
        // new utilization should be always less than EXP
        if (newUtilization >= EXPONENT) {
            revert Error.ExceedsAcceptableRange();
        }

        // temporary value to store the new utilization
        prover.intendedComputeUtilization = newUtilization;

        // block number after which this intent which execute
        reduceComputeRequestBlock[_proverAddress] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestComputeDecrease(_proverAddress, newUtilization);
    }

    /**
     * @notice Free up the unused compute. intendToReduceCompute must have been called before this function
     */
    function decreaseDeclaredCompute() external {
        address _proverAddress = _msgSender();

        Prover storage prover = proverRegistry[_proverAddress];

        if (prover.proverData.length == 0 || prover.rewardAddress == address(0)) {
            revert Error.InvalidProver();
        }

        if (prover.intendedComputeUtilization == EXPONENT) {
            revert Error.ReduceComputeRequestNotInPlace();
        }

        uint256 newTotalCompute = (prover.intendedComputeUtilization * prover.declaredCompute) / EXPONENT;
        uint256 computeToRelease = prover.declaredCompute - newTotalCompute;

        if (newTotalCompute < prover.computeConsumed) {
            revert Error.InsufficientProverComputeAvailable();
        }

        if (newTotalCompute < prover.sumOfComputeAllocations) {
            revert Error.InsufficientProverComputeAvailable();
        }

        prover.declaredCompute = newTotalCompute;
        prover.intendedComputeUtilization = EXPONENT;

        if (!(block.number >= reduceComputeRequestBlock[_proverAddress] && reduceComputeRequestBlock[_proverAddress] != 0)) {
            revert Error.ReductionRequestNotValid();
        }

        delete reduceComputeRequestBlock[_proverAddress];
        emit DecreaseCompute(_proverAddress, computeToRelease);
    }

    /**
     * @notice Deregister the prover
     */
    function deregister() external nonReentrant {
        address _proverAddress = _msgSender();
        Prover memory prover = proverRegistry[_proverAddress];

        if (prover.sumOfComputeAllocations != 0) {
            revert Error.CannotLeaveWithActiveMarket();
        }

        delete proverRegistry[_proverAddress];

        emit DeregisteredProver(_proverAddress);
    }

    /**
     * @notice update the encryption key
     */
    function updateEncryptionKey(uint256 marketId, bytes memory attestationData, bytes calldata enclaveSignature) external {
        // prover here is _msgSender()
        _updateEncryptionKey(_msgSender(), marketId, attestationData, enclaveSignature);
    }


    function _updateEncryptionKey(
        address proverAddress,
        uint256 marketId,
        bytes memory attestationData,
        bytes calldata enclaveSignature
    ) internal {
        Prover memory prover = proverRegistry[proverAddress];

        // just an extra check to prevent spam
        if (prover.rewardAddress == address(0)) {
            revert Error.CannotBeZero();
        }

        // only for knowing if the given market is private or public
        (, bytes32 proverImageId) = _readMarketData(marketId);
        if (!proverImageId.IS_ENCLAVE()) {
            revert Error.PublicMarketsDontNeedKey();
        }

        if (!ENTITY_KEY_REGISTRY.isImageInFamily(attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), marketId.PROVER_FAMILY_ID())) {
            revert Error.IncorrectImageId();
        }

        bytes memory pubkey = attestationData.GET_PUBKEY();

        attestationData.VERIFY_ENCLAVE_SIGNATURE(enclaveSignature, proverAddress);

        // don't whitelist, because same imageId must be used to update the key
        ENTITY_KEY_REGISTRY.updatePubkey(proverAddress, marketId, pubkey, attestationData);
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
     * @notice Remove prover's encryption key
     */
    function removeEncryptionKey(uint256 marketId) external {
        // proverAddress = _msgSender();
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
        address proverAddress = _msgSender();

        Prover storage prover = proverRegistry[proverAddress];
        ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][marketId];

        // proof generation time can't be zero.
        // compute required per proof can't be zero
        if (prover.rewardAddress == address(0) || proposedTime == 0 || computePerRequestRequired == 0) {
            revert Error.CannotBeZero();
        }

        // only for checking if any market id valid or not
        (address marketVerifierContractAddress, ) = _readMarketData(marketId);
        if (marketVerifierContractAddress == address(0)) {
            revert Error.InvalidMarket();
        }

        // prevents re-joining
        if (info.state != ProverState.NULL) {
            revert Error.AlreadyJoinedMarket();
        }

        // sum of compute allocation of all supported markets
        prover.sumOfComputeAllocations += computePerRequestRequired;

        // ensures that prover will support atleast 1 request for every market
        if (prover.sumOfComputeAllocations > prover.declaredCompute) {
            revert Error.CannotBeMoreThanDeclaredCompute();
        }

        // increment the number of active market places supported
        prover.activeMarketplaces++;

        // update market specific info for the prover
        proverInfoPerMarket[proverAddress][marketId] = ProverInfoPerMarket(
            ProverState.JOINED,
            computePerRequestRequired,
            proofGenerationCost,
            proposedTime,
            0
        );

        if (updateMarketDedicatedKey) {
            _updateEncryptionKey(proverAddress, marketId, attestationData, enclaveSignature);
        }
        emit JoinedMarketplace(proverAddress, marketId, computePerRequestRequired);
    }

    function _readMarketData(uint256 marketId) internal view returns (address, bytes32) {
        (IVerifier _verifier, bytes32 proverImageId, , , , , ) = proofMarketplace.marketData(marketId);

        return (address(_verifier), proverImageId);
    }

    function getProverState(address proverAddress, uint256 marketId) public view returns (ProverState, uint256) {
        ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][marketId];
        Prover memory prover = proverRegistry[proverAddress];

        if (info.state == ProverState.NULL) {
            return (ProverState.NULL, 0);
        }

        if (info.state == ProverState.REQUESTED_FOR_EXIT) {
            return (ProverState.REQUESTED_FOR_EXIT, 0);
        }

        uint256 idleCapacity = _maxReducableCompute(proverAddress);

        if (info.state != ProverState.NULL && idleCapacity == 0) {
            return (ProverState.NO_COMPUTE_AVAILABLE, 0);
        }

        if (idleCapacity == prover.declaredCompute) {
            return (ProverState.JOINED, idleCapacity);
        }

        if (idleCapacity != 0 && idleCapacity < prover.declaredCompute) {
            return (ProverState.WIP, idleCapacity);
        }
        return (ProverState.NULL, 0);
    }

    function _maxReducableCompute(address proverAddress) internal view returns (uint256) {
        Prover memory prover = proverRegistry[proverAddress];

        uint256 maxUsableCompute = (prover.declaredCompute * prover.intendedComputeUtilization) / EXPONENT;

        if (maxUsableCompute < prover.computeConsumed) {
            return 0;
        }

        return maxUsableCompute - prover.computeConsumed;
    }

    function leaveMarketplaces(uint256[] calldata marketIds) external {
        for (uint256 index = 0; index < marketIds.length; index++) {
            // proverAddress = _msgSender();
            _leaveMarketplace(_msgSender(), marketIds[index]);
        }
    }

    function leaveMarketplace(uint256 marketId) external {
        // proverAddress = _msgSender();
        _leaveMarketplace(_msgSender(), marketId);
    }

    function requestForExitMarketplaces(uint256[] calldata marketIds) external {
        for (uint256 index = 0; index < marketIds.length; index++) {
            // proverAddress = _msgSender();
            _requestForExitMarketplace(_msgSender(), marketIds[index]);
        }
    }

    function requestForExitMarketplace(uint256 marketId) external {
        // proverAddress = _msgSender();
        _requestForExitMarketplace(_msgSender(), marketId);
    }

    function _requestForExitMarketplace(address proverAddress, uint256 marketId) internal {
        (ProverState state, ) = getProverState(proverAddress, marketId);

        // only valid provers can exit the market
        if (!(state != ProverState.NULL && state != ProverState.REQUESTED_FOR_EXIT)) {
            revert Error.OnlyValidProversCanRequestExit();
        }
        ProverInfoPerMarket storage info = proverInfoPerMarket[proverAddress][marketId];

        info.state = ProverState.REQUESTED_FOR_EXIT;

        // alerts matching engine to stop assinging the requests of given market
        emit RequestExitMarketplace(proverAddress, marketId);

        // if there are no active requests, proceed to leave market plaes
        if (info.activeRequests == 0) {
            _leaveMarketplace(proverAddress, marketId);
        }
    }

    function _leaveMarketplace(address proverAddress, uint256 marketId) internal {
        (IVerifier marketVerifier, , , , , , ) = proofMarketplace.marketData(marketId);

        // check if market is valid
        if (address(marketVerifier) == address(0)) {
            revert Error.InvalidMarket();
        }

        ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][marketId];

        if (info.state == ProverState.NULL) {
            revert Error.InvalidProverStatePerMarket();
        }

        // check if there are any active requestsw
        if (info.activeRequests != 0) {
            revert Error.CannotLeaveMarketWithActiveRequest();
        }

        Prover storage prover = proverRegistry[proverAddress];

        prover.sumOfComputeAllocations -= info.computePerRequestRequired;
        prover.activeMarketplaces -= 1;

        delete proverInfoPerMarket[proverAddress][marketId];
        emit LeftMarketplace(proverAddress, marketId);
    }

    /**
     * @notice Should be called by proof market place only, PMP is assigned SLASHER_ROLE, called when provers is about to be slashed
     */
    function releaseProverResources(
        address proverAddress,
        uint256 marketId
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (ProverState state, ) = getProverState(proverAddress, marketId);

        // All states = NULL,JOINED,NO_COMPUTE_AVAILABLE,WIP,REQUESTED_FOR_EXIT
        // only provers in WIP, REQUESTED_FOR_EXIT, NO_COMPUTE_AVAILABLE can submit the request, NULL and JOINED can't
        if (state == ProverState.NULL || state == ProverState.JOINED) {
            revert Error.CannotBeSlashed();
        }

        Prover storage prover = proverRegistry[proverAddress];
        ProverInfoPerMarket storage info = proverInfoPerMarket[proverAddress][marketId];

        info.activeRequests--;

        prover.computeConsumed -= info.computePerRequestRequired;
        emit ComputeReleased(proverAddress, info.computePerRequestRequired);
    }

    function assignProverTask(
        uint256 bidId,
        address proverAddress,
        uint256 marketId
    ) external nonReentrant onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (ProverState state, uint256 idleCapacity) = getProverState(proverAddress, marketId);

        if (!(state == ProverState.JOINED || state == ProverState.WIP)) {
            revert Error.AssignOnlyToIdleProvers();
        }

        Prover storage prover = proverRegistry[proverAddress];
        ProverInfoPerMarket storage info = proverInfoPerMarket[proverAddress][marketId];

        // requiredCompute <= idleCapacity
        if (info.computePerRequestRequired > idleCapacity) {
            revert Error.InsufficientProverComputeAvailable();
        }
        if (info.activeRequests > PARALLEL_REQUESTS_UPPER_LIMIT) {
            revert Error.MaxParallelRequestsPerMarketExceeded();
        }

        uint256 computeConsumed = info.computePerRequestRequired;
        prover.computeConsumed += computeConsumed;

        IStakingManager(stakingManager).onTaskAssignment(bidId, proverAddress);

        info.activeRequests++;
        emit ComputeLocked(proverAddress, computeConsumed);
    }

    function completeProverTask(
        uint256 bidId,
        address proverAddress,
        uint256 marketId,
        uint256 stakeToRelease
    ) external onlyRole(PROOF_MARKET_PLACE_ROLE) {
        (ProverState state, ) = getProverState(proverAddress, marketId);

        // All states = NULL,JOINED,NO_COMPUTE_AVAILABLE,WIP,REQUESTED_FOR_EXIT
        // only provers in WIP, REQUESTED_FOR_EXIT, NO_COMPUTE_AVAILABLE can submit the request, NULL and JOINED can't
        if (state == ProverState.NULL || state == ProverState.JOINED) {
            revert Error.OnlyWorkingProvers();
        }

        Prover storage prover = proverRegistry[proverAddress];
        ProverInfoPerMarket storage info = proverInfoPerMarket[proverAddress][marketId];

        uint256 computeReleased = info.computePerRequestRequired;
        prover.computeConsumed -= computeReleased;

        IStakingManager(stakingManager).onTaskCompletion(bidId, proverAddress, stakeToRelease);

        info.activeRequests--;
        emit ComputeReleased(proverAddress, computeReleased);
    }

    function getProverAssignmentDetails(address proverAddress, uint256 marketId) public view returns (uint256, uint256) {
        ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][marketId];

        return (info.proofGenerationCost, info.proposedTime);
    }

    function getProverRewardDetails(address proverAddress, uint256 marketId) public view returns (address, uint256) {
        ProverInfoPerMarket memory info = proverInfoPerMarket[proverAddress][marketId];
        Prover memory prover = proverRegistry[proverAddress];

        return (prover.rewardAddress, info.proofGenerationCost);
    }

    function addStakeCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit AddedStake(proverAddress, token, amount);
    }

    function intendToReduceStakeCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit IntendToReduceStake(proverAddress, token, amount);
    }
    
    function removeStakeCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit RemovedStake(proverAddress, token, amount);
    }

    function stakeLockImposedCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeLockImposed(proverAddress, token, amount);
    }

    function stakeLockReleasedCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeLockReleased(proverAddress, token, amount);
    }

    function stakeSlashedCallback(address proverAddress, address token, uint256 amount) external override {
        if(!STAKING_MANAGER.isEnabledPool(msg.sender)){
            revert Error.InvalidContractAddress();
        }

        emit StakeSlashed(proverAddress, token, amount);
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
