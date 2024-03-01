// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "./EntityKeyRegistry.sol";
import "./lib/Error.sol";
import "./ProofMarketplace.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
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
    )
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._grantRole(role, account);
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, Error.CANNOT_BE_ADMIN_LESS);
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
        __AccessControlEnumerable_init_unchained();
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
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

        require(generatorData.length != 0, Error.CANNOT_BE_ZERO);
        require(rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(declaredCompute != 0, Error.CANNOT_BE_ZERO);

        // prevents registering multiple times, unless deregistered
        require(generator.rewardAddress == address(0), Error.GENERATOR_ALREADY_EXISTS);

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
        require(newRewardAddress != address(0), Error.CANNOT_BE_ZERO);
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        generator.rewardAddress = newRewardAddress;

        emit ChangedGeneratorRewardAddress(_generatorAddress, newRewardAddress);
    }

    /**
     * @notice Increase generator's compute
     */
    function increaseDeclaredCompute(uint256 computeToIncrease) external {
        address _generatorAddress = _msgSender();
        Generator storage generator = generatorRegistry[_generatorAddress];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

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

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        // if request is already in place, this will ICU will be less than EXP (as per design)
        require(generator.intendedComputeUtilization == EXPONENT, Error.REQUEST_ALREADY_IN_PLACE);

        // new utilization should be always less than EXP
        require(newUtilization < EXPONENT, Error.EXCEEDS_ACCEPTABLE_RANGE);

        // new utilization after update
        uint256 newTotalCompute = (newUtilization * generator.declaredCompute) / EXPONENT;

        // this is min compute requires for atleast 1 request from each supported market
        require(newTotalCompute >= generator.sumOfComputeAllocations, Error.EXCEEDS_ACCEPTABLE_RANGE);

        // ensures that new utilization is not too small to release and prevent generator dead lock
        // uint256 computeToRelease = generator.declaredCompute - newTotalCompute;
        require(generator.declaredCompute - newTotalCompute != 0, Error.CANNOT_BE_ZERO);

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
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(generator.intendedComputeUtilization != EXPONENT, Error.REDUCE_COMPUTE_REQUEST_NOT_IN_PLACE);

        uint256 newTotalCompute = (generator.intendedComputeUtilization * generator.declaredCompute) / EXPONENT;
        uint256 computeToRelease = generator.declaredCompute - newTotalCompute;

        require(newTotalCompute >= generator.computeConsumed, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);
        require(newTotalCompute >= generator.sumOfComputeAllocations, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);

        generator.declaredCompute = newTotalCompute;
        generator.intendedComputeUtilization = EXPONENT;

        require(
            block.number >= reduceComputeRequestBlock[generatorAddress] &&
                reduceComputeRequestBlock[generatorAddress] != 0,
            Error.REDUCTION_REQUEST_NOT_VALID
        );

        delete reduceComputeRequestBlock[generatorAddress];
        emit DecreaseCompute(generatorAddress, computeToRelease);
    }

    /**
     * @notice Add/Increase stake
     */
    function stake(address generatorAddress, uint256 amount) external nonReentrant returns (uint256) {
        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(amount != 0, Error.CANNOT_BE_ZERO);

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

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        // if request is already in place, this will ICU will be less than EXP (as per design)
        require(generator.intendedStakeUtilization == EXPONENT, Error.REQUEST_ALREADY_IN_PLACE);

        // new utilization should be always less than EXP
        require(newUtilization < EXPONENT, Error.EXCEEDS_ACCEPTABLE_RANGE);

        generator.intendedStakeUtilization = newUtilization;

        // new utilization after update
        uint256 newTotalStake = (newUtilization * generator.totalStake) / EXPONENT;

        // ensures that new utilization is not too small to release and prevent generator dead lock
        // uint256 stakeToRelease = generator.totalStake - newTotalStake;
        require(generator.totalStake - newTotalStake != 0, Error.CANNOT_BE_ZERO);

        unstakeRequestBlock[_generatorAddress] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestStakeDecrease(_generatorAddress, newUtilization);
    }

    /**
     * @notice Free up the unused stake. intendToReduceStake must have been called before this function
     */
    function unstake(address to) external nonReentrant {
        address generatorAddress = _msgSender();

        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(generator.intendedStakeUtilization != EXPONENT, Error.UNSTAKE_REQUEST_NOT_IN_PLACE);

        uint256 newTotalStake = (generator.intendedStakeUtilization * generator.totalStake) / EXPONENT;

        uint256 amountToTransfer = generator.totalStake - newTotalStake;

        // prevent removing amount unless existing stake is not released
        require(newTotalStake >= generator.stakeLocked, Error.INSUFFICIENT_STAKE_TO_LOCK);

        // amountToTransfer will be non-zero
        STAKING_TOKEN.safeTransfer(to, amountToTransfer);

        generator.totalStake = newTotalStake;
        generator.intendedStakeUtilization = EXPONENT;

        require(
            block.number >= unstakeRequestBlock[generatorAddress] && unstakeRequestBlock[generatorAddress] != 0,
            Error.REDUCTION_REQUEST_NOT_VALID
        );
        delete unstakeRequestBlock[generatorAddress];
        emit RemovedStake(generatorAddress, amountToTransfer);
    }

    /**
     * @notice Deregister the generator
     */
    function deregister(address refundAddress) external nonReentrant {
        address _generatorAddress = _msgSender();
        Generator memory generator = generatorRegistry[_generatorAddress];

        require(generator.sumOfComputeAllocations == 0, Error.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET);
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

        require(
            expectedImageId != bytes32(0) || expectedImageId != HELPER.NO_ENCLAVE_ID,
            Error.PUBLIC_MARKETS_DONT_NEED_KEY
        );

        require(expectedImageId == attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), Error.INCORRECT_IMAGE_ID);

        // just an extra check to prevent spam
        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO);

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
        require(expectedIvsImageId == attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), Error.INCORRECT_IMAGE_ID);

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

        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);

        (address marketVerifierContractAddress, bytes32 expectedImageId) = _readMarketData(marketId);

        // prevent joining invalid market
        require(marketVerifierContractAddress != address(0), Error.INVALID_MARKET);

        // prevents re-joining
        require(info.state == GeneratorState.NULL, Error.ALREADY_JOINED_MARKET);

        // proof generation time can't be zero.
        require(proposedTime != 0, Error.CANNOT_BE_ZERO);

        // compute required per proof
        require(computePerRequestRequired != 0, Error.CANNOT_BE_ZERO);

        // sum of compute allocation of all supported markets
        generator.sumOfComputeAllocations += computePerRequestRequired;

        // ensures that generator will support atleast 1 request for every market
        require(
            generator.sumOfComputeAllocations <= generator.declaredCompute,
            Error.CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE
        );

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
            require(expectedImageId == attestationData.GET_IMAGE_ID_FROM_ATTESTATION(), Error.INCORRECT_IMAGE_ID);

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
        require(
            state != GeneratorState.NULL && state != GeneratorState.REQUESTED_FOR_EXIT,
            Error.ONLY_VALID_GENERATORS_CAN_REQUEST_EXIT
        );
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
        require(address(marketVerifier) != address(0), Error.INVALID_MARKET);

        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        require(info.state != GeneratorState.NULL, Error.INVALID_GENERATOR_STATE_PER_MARKET);

        // check if there are any active requestsw
        require(info.activeRequests == 0, Error.CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST);

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
        require(
            state == GeneratorState.WIP ||
                state == GeneratorState.REQUESTED_FOR_EXIT ||
                state == GeneratorState.NO_COMPUTE_AVAILABLE,
            Error.CAN_N0T_BE_SLASHED
        );

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
        require(state == GeneratorState.JOINED || state == GeneratorState.WIP, Error.ASSIGN_ONLY_TO_IDLE_GENERATORS);

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        // requiredCompute <= idleCapacity
        require(info.computePerRequestRequired <= idleCapacity, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);
        require(info.activeRequests <= PARALLEL_REQUESTS_UPPER_LIMIT, Error.MAX_PARALLEL_REQUESTS_PER_MARKET_EXCEEDED);

        uint256 availableStake = _maxReducableStake(generatorAddress);
        require(availableStake >= stakeToLock, Error.INSUFFICIENT_STAKE_TO_LOCK);

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
        require(
            state == GeneratorState.WIP ||
                state == GeneratorState.REQUESTED_FOR_EXIT ||
                state == GeneratorState.NO_COMPUTE_AVAILABLE,
            Error.ONLY_WORKING_GENERATORS
        );

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
