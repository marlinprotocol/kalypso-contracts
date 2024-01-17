// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./ProofMarketPlace.sol";
import "./EntityKeyRegistry.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    HELPER
{
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
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, "Cannot be adminless");
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable STAKING_TOKEN;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");

    uint256 public constant PARALLEL_REQUESTS_UPPER_LIMIT = 100;

    uint256 private constant EXPONENT = 10 ** 18;

    uint256 public constant UNLOCK_WAIT_BLOCKS = 100;

    uint256 public constant REDUCTION_REQUEST_BLOCK_GAP = 1;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => Generator) public generatorRegistry;
    mapping(address => mapping(uint256 => GeneratorInfoPerMarket)) public generatorInfoPerMarket;

    mapping(address => uint256) unstakeRequestBlock;
    mapping(address => uint256) reduceComputeRequestBlock;

    ProofMarketPlace public proofMarketPlace;

    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

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
        uint256 activeMarketPlaces;
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

    event JoinedMarketPlace(address indexed generator, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketPlace(address indexed generator, uint256 indexed marketId);
    event LeftMarketplace(address indexed generator, uint256 indexed marketId);

    event AddedStake(address indexed generator, uint256 amount);
    event RequestStakeDecrease(address indexed generator, uint256 intendedUtilization);
    event RemovedStake(address indexed generator, uint256 amount);

    event IncreasedCompute(address indexed generator, uint256 compute);
    event RequestComputeDecrease(address indexed generator, uint256 intendedUtilization);
    event DecreaseCompute(address indexed generator, uint256 compute);

    //-------------------------------- Events end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _stakingToken, EntityKeyRegistry _entityRegistry) {
        STAKING_TOKEN = _stakingToken;
        ENTITY_KEY_REGISTRY = _entityRegistry;
    }

    function initialize(address _admin, address _proofMarketPlace) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SLASHER_ROLE, _proofMarketPlace);
        proofMarketPlace = ProofMarketPlace(_proofMarketPlace);
    }

    function register(
        address rewardAddress,
        uint256 declaredCompute,
        uint256 initialStake,
        bytes memory generatorData
    ) external {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generatorData.length != 0, Error.CANNOT_BE_ZERO);
        require(rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(declaredCompute != 0, Error.CANNOT_BE_ZERO);

        require(generator.rewardAddress == address(0), Error.GENERATOR_ALREADY_EXISTS);

        generatorRegistry[_msgSender] = Generator(
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

        if (initialStake != 0) {
            STAKING_TOKEN.safeTransferFrom(_msgSender, address(this), initialStake);
        }
        emit RegisteredGenerator(_msgSender, declaredCompute, initialStake);
    }

    function changeRewardAddress(address newRewardAddress) external {
        address _msgSender = msg.sender;
        Generator storage generator = generatorRegistry[_msgSender];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        generator.rewardAddress = newRewardAddress;

        emit ChangedGeneratorRewardAddress(_msgSender, newRewardAddress);
    }

    function increaseDeclaredCompute(uint256 computeToIncrease) external {
        address _msgSender = msg.sender;
        Generator storage generator = generatorRegistry[_msgSender];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        generator.declaredCompute += computeToIncrease;

        emit IncreasedCompute(_msgSender, computeToIncrease);
    }

    function intendToReduceCompute(uint256 newUtilization) external {
        address _msgSender = msg.sender;
        Generator storage generator = generatorRegistry[_msgSender];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        require(generator.intendedComputeUtilization == EXPONENT, Error.REQUEST_ALREADY_IN_PLACE);
        require(newUtilization < EXPONENT, Error.EXCEEDS_ACCEPTABLE_RANGE);

        uint256 newTotalCompute = (newUtilization * generator.declaredCompute) / EXPONENT;

        // ensures no spamming in the contracts.
        require(newTotalCompute >= generator.sumOfComputeAllocations, Error.EXCEEDS_ACCEPTABLE_RANGE);

        generator.intendedComputeUtilization = newUtilization;

        reduceComputeRequestBlock[_msgSender] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestComputeDecrease(_msgSender, newUtilization);
    }

    function decreaseDeclaredCompute() external {
        address generatorAddress = msg.sender;

        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(generator.intendedComputeUtilization != EXPONENT, Error.REDUCE_COMPUTE_REQUEST_NOT_IN_PLACE);

        uint256 newTotalCompute = (generator.intendedComputeUtilization * generator.declaredCompute) / EXPONENT;
        uint256 computeToRelease = generator.declaredCompute - newTotalCompute;

        require(newTotalCompute >= generator.computeConsumed, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);
        require(newTotalCompute >= generator.sumOfComputeAllocations, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);

        require(computeToRelease != 0, Error.CANNOT_BE_ZERO);

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

    function stake(address generatorAddress, uint256 amount) external returns (uint256) {
        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(amount != 0, Error.CANNOT_BE_ZERO);

        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        generator.totalStake += amount;

        emit AddedStake(generatorAddress, amount);
        return generator.totalStake;
    }

    function intendToReduceStake(uint256 newUtilization) external {
        address _msgSender = msg.sender;
        Generator storage generator = generatorRegistry[_msgSender];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        require(generator.intendedStakeUtilization == EXPONENT, Error.REQUEST_ALREADY_IN_PLACE);
        require(newUtilization < EXPONENT, Error.EXCEEDS_ACCEPTABLE_RANGE);

        generator.intendedStakeUtilization = newUtilization;

        unstakeRequestBlock[_msgSender] = block.number + REDUCTION_REQUEST_BLOCK_GAP;
        emit RequestStakeDecrease(_msgSender, newUtilization);
    }

    function unstake(address to) external {
        address generatorAddress = msg.sender;

        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(generator.intendedStakeUtilization != EXPONENT, Error.UNSTAKE_REQUEST_NOT_IN_PLACE);

        uint256 newTotalStake = (generator.intendedStakeUtilization * generator.totalStake) / EXPONENT;
        uint256 amountToTransfer = generator.totalStake - newTotalStake;
        require(amountToTransfer != 0, Error.CANNOT_BE_ZERO);

        require(newTotalStake >= generator.stakeLocked, Error.INSUFFICIENT_STAKE_TO_LOCK);
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

    function deregister(address refundAddress) external {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generator.sumOfComputeAllocations == 0, Error.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET);
        STAKING_TOKEN.safeTransfer(refundAddress, generator.totalStake);
        delete generatorRegistry[_msgSender];

        emit DeregisteredGenerator(_msgSender);
    }

    function updateEncryptionKey(bytes memory attestation_data, bytes calldata enclaveSignature) external {
        address _msgSender = _msgSender();
        Generator memory generator = generatorRegistry[_msgSender];
        // just an extra check to prevent spam
        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO);

        (bytes memory pubkey, address _address) = HELPER.getPubkeyAndAddress(attestation_data);

        bytes32 messageHash = keccak256(abi.encode(_msgSender));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, enclaveSignature);
        require(signer == _address, Error.INVALID_ENCLAVE_SIGNATURE);

        ENTITY_KEY_REGISTRY.updatePubkey(_msgSender, pubkey, attestation_data);
    }

    function joinMarketPlace(
        uint256 marketId,
        uint256 computePerRequestRequired,
        uint256 proofGenerationCost,
        uint256 proposedTime
    ) external {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);

        require(proofMarketPlace.verifier(marketId) != address(0), Error.INVALID_MARKET);
        require(info.state == GeneratorState.NULL, Error.ALREADY_JOINED_MARKET);

        require(proposedTime != 0, Error.CANNOT_BE_ZERO);
        require(computePerRequestRequired != 0, Error.CANNOT_BE_ZERO);

        generator.sumOfComputeAllocations += computePerRequestRequired;
        require(
            generator.sumOfComputeAllocations <= generator.declaredCompute,
            Error.CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE
        );
        generator.activeMarketPlaces++;

        generatorInfoPerMarket[generatorAddress][marketId] = GeneratorInfoPerMarket(
            GeneratorState.JOINED,
            computePerRequestRequired,
            proofGenerationCost,
            proposedTime,
            0
        );

        emit JoinedMarketPlace(generatorAddress, marketId, computePerRequestRequired);
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

    function leaveMarketPlaces(uint256[] calldata marketIds) external {
        address generatorAddress = msg.sender;
        for (uint256 index = 0; index < marketIds.length; index++) {
            _leaveMarketPlace(generatorAddress, marketIds[index]);
        }
    }

    function leaveMarketPlace(uint256 marketId) external {
        address generatorAddress = msg.sender;
        _leaveMarketPlace(generatorAddress, marketId);
    }

    function requestForExitMarketPlaces(uint256[] calldata marketIds) external {
        address generatorAddress = msg.sender;
        for (uint256 index = 0; index < marketIds.length; index++) {
            _requestForExitMarketPlace(generatorAddress, marketIds[index]);
        }
    }

    function requestForExitMarketPlace(uint256 marketId) external {
        address generatorAddress = msg.sender;
        _requestForExitMarketPlace(generatorAddress, marketId);
    }

    function _requestForExitMarketPlace(address generatorAddress, uint256 marketId) internal {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);
        require(
            state != GeneratorState.NULL && state != GeneratorState.REQUESTED_FOR_EXIT,
            Error.ONLY_VALID_GENERATORS_CAN_REQUEST_EXIT
        );
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        info.state = GeneratorState.REQUESTED_FOR_EXIT;

        emit RequestExitMarketPlace(generatorAddress, marketId);
    }

    function _leaveMarketPlace(address generatorAddress, uint256 marketId) internal {
        require(proofMarketPlace.verifier(marketId) != address(0), Error.INVALID_MARKET);
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        require(info.state != GeneratorState.NULL, Error.INVALID_GENERATOR_STATE_PER_MARKET);
        require(info.activeRequests == 0, Error.CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST);

        Generator storage generator = generatorRegistry[generatorAddress];
        generator.sumOfComputeAllocations -= info.computePerRequestRequired;
        generator.activeMarketPlaces -= 1;

        delete generatorInfoPerMarket[generatorAddress][marketId];
        emit LeftMarketplace(generatorAddress, marketId);
    }

    function slashGenerator(
        address generatorAddress,
        uint256 marketId,
        uint256 slashingAmount,
        address rewardAddress
    ) external onlyRole(SLASHER_ROLE) returns (uint256) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);
        // TODO: Refine this
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
    ) external onlyRole(SLASHER_ROLE) {
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
    ) external onlyRole(SLASHER_ROLE) {
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
}
