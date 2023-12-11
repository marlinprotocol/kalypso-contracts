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
import "./lib/Error.sol";

// import "hardhat/console.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable
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

    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    uint256 public constant PARALLEL_REQUESTS_UPPER_LIMIT = 100;

    uint256 private constant EXPONENT = 10e18;

    uint256 public constant UNLOCK_WAIT_BLOCKS = 100;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => Generator) public generatorRegistry;
    mapping(address => mapping(uint256 => GeneratorInfoPerMarket)) public generatorInfoPerMarket;

    mapping(uint256 => UnstakeRequest) public unstakingRequests;
    uint256 public unstakingRequestCount;

    mapping(uint256 => DecreaseComputeRequest) public decreaseComputeRequests;
    uint256 public decreaseComputeRequestCount;

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
        bytes generatorData;
    }

    struct GeneratorInfoPerMarket {
        GeneratorState state;
        uint256 computeAllocation;
        uint256 proofGenerationCost;
        uint256 proposedTime;
        uint256 activeRequests;
    }

    struct UnstakeRequest {
        address generator;
        uint256 amount;
        uint256 unlockingBlock;
    }

    struct DecreaseComputeRequest {
        address generator;
        uint256 compute;
        uint256 unlockingBlock;
    }

    //-------------------------------- State variables end --------------------------------//

    //-------------------------------- Events end --------------------------------//

    event RegisteredGenerator(address indexed generator);
    event DeregisteredGenerator(address indexed generator);

    event ChangedGeneratorRewardAddress(address indexed generator, address newRewardAddress);

    event JoinedMarketPlace(address indexed generator, uint256 indexed marketId, uint256 computeAllocation);
    event RequestExitMarketPlace(address indexed generator, uint256 indexed marketId);
    event LeftMarketplace(address indexed generator, uint256 indexed marketId);

    event AddedStake(address indexed generator, uint256 amount);
    event RequestUnstake(address indexed generator, uint256 indexed requestId, uint256 amount);
    event RemovedStake(address indexed generator, uint256 amount);

    event IncreasedCompute(address indexed generator, uint256 compute);
    event RequestDecreaseCompute(address indexed generator, uint256 indexed requestId, uint256 compute);
    event DecreasedCompute(address indexed generator, uint256 compute);

    //-------------------------------- Events end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _stakingToken) {
        STAKING_TOKEN = _stakingToken;
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

    function register(address rewardAddress, uint256 declaredCompute, bytes memory generatorData) external {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generatorData.length != 0, Error.CANNOT_BE_ZERO);
        require(rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(declaredCompute != 0, Error.CANNOT_BE_ZERO);

        require(generator.rewardAddress == address(0), Error.GENERATOR_ALREADY_EXISTS);

        generatorRegistry[_msgSender] = Generator(rewardAddress, 0, 0, 0, 0, 0, declaredCompute, generatorData);

        emit RegisteredGenerator(_msgSender);
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

    function requestComputeReduce(uint256 computeToDecrease) external {
        address _msgSender = msg.sender;
        Generator storage generator = generatorRegistry[_msgSender];

        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO); // Check if generator is valid
        require(generator.generatorData.length != 0, Error.CANNOT_BE_ZERO);

        uint256 availableCompute = generator.declaredCompute - generator.computeConsumed;
        require(availableCompute >= computeToDecrease, Error.INSUFFICIENT_COMPUTE_TO_REDUCE);

        generator.computeConsumed += availableCompute;
        uint256 releaseBlock = block.number + UNLOCK_WAIT_BLOCKS;

        decreaseComputeRequests[decreaseComputeRequestCount] = DecreaseComputeRequest(
            _msgSender,
            computeToDecrease,
            releaseBlock
        );
        emit RequestDecreaseCompute(_msgSender, decreaseComputeRequestCount, computeToDecrease);
    }

    function decreaseDeclaredCompute(uint256 requestId) external {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];

        DecreaseComputeRequest memory decreaseComputeRequest = decreaseComputeRequests[requestId];
        require(
            decreaseComputeRequest.generator == generatorAddress,
            Error.ONLY_GENERATOR_CAN_DECREASE_COMPUTE_WITH_REQUEST
        );
        require(block.number >= decreaseComputeRequest.unlockingBlock, Error.ONLY_AFTER_DEADLINE);

        generator.declaredCompute -= decreaseComputeRequest.compute;
        generator.computeConsumed -= decreaseComputeRequest.compute;

        emit DecreasedCompute(generatorAddress, decreaseComputeRequest.compute);

        delete decreaseComputeRequests[requestId];
    }

    function deregister(address refundAddress) external {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generator.sumOfComputeAllocations == 0, Error.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET);
        STAKING_TOKEN.safeTransfer(refundAddress, generator.totalStake);
        delete generatorRegistry[_msgSender];

        emit DeregisteredGenerator(_msgSender);
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

    function requestUnstake(uint256 amount) external {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];

        uint256 availableAmount = generator.totalStake - generator.stakeLocked;
        require(amount <= availableAmount, Error.CAN_NOT_WITHDRAW_MORE_UNLOCKED_AMOUNT);

        generator.stakeLocked += amount;

        uint256 unstakeBlock = block.number + UNLOCK_WAIT_BLOCKS;
        unstakingRequests[unstakingRequestCount] = UnstakeRequest(generatorAddress, amount, unstakeBlock);
        uint256 requestId = unstakingRequestCount;

        emit RequestUnstake(generatorAddress, requestId, amount);
        unstakingRequestCount++;
    }

    function unstake(uint256 requestId, address recipient) external returns (uint256) {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];

        UnstakeRequest memory unstakeRequest = unstakingRequests[requestId];
        require(unstakeRequest.generator == generatorAddress, Error.ONLY_GENERATOR_CAN_UNSTAKE_WITH_REQUEST);
        require(block.number >= unstakeRequest.unlockingBlock, Error.ONLY_AFTER_DEADLINE);

        generator.totalStake -= unstakeRequest.amount;
        generator.stakeLocked -= unstakeRequest.amount;

        emit RemovedStake(generatorAddress, unstakeRequest.amount);

        delete unstakingRequests[requestId];
        STAKING_TOKEN.safeTransfer(recipient, unstakeRequest.amount);

        return generator.totalStake;
    }

    function joinMarketPlace(
        uint256 marketId,
        uint256 computeAllocation,
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
        require(computeAllocation != 0, Error.CANNOT_BE_ZERO);

        generator.sumOfComputeAllocations += computeAllocation;
        require(
            generator.sumOfComputeAllocations <= generator.declaredCompute,
            Error.CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE
        );
        generator.activeMarketPlaces++;

        generatorInfoPerMarket[generatorAddress][marketId] = GeneratorInfoPerMarket(
            GeneratorState.JOINED,
            computeAllocation,
            proofGenerationCost,
            proposedTime,
            0
        );

        emit JoinedMarketPlace(generatorAddress, marketId, computeAllocation);
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

        uint256 idleCapacity = generator.declaredCompute - generator.computeConsumed;
        if (idleCapacity == generator.declaredCompute) {
            return (GeneratorState.JOINED, generator.declaredCompute);
        }

        if (idleCapacity != 0 && idleCapacity < generator.declaredCompute) {
            return (GeneratorState.WIP, idleCapacity);
        }

        if (info.state != GeneratorState.NULL && idleCapacity == 0) {
            return (GeneratorState.NO_COMPUTE_AVAILABLE, 0);
        }
        return (GeneratorState.NULL, 0);
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
        require(info.activeRequests == 0, Error.CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST);

        Generator storage generator = generatorRegistry[generatorAddress];
        generator.sumOfComputeAllocations -= info.computeAllocation;
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

        generator.computeConsumed -= info.computeAllocation;

        STAKING_TOKEN.safeTransfer(rewardAddress, slashingAmount);

        return generator.totalStake;
    }

    function assignGeneratorTask(
        address generatorAddress,
        uint256 marketId,
        uint256 amountToLock
    ) external onlyRole(SLASHER_ROLE) {
        (GeneratorState state, uint256 idleCapacity) = getGeneratorState(generatorAddress, marketId);
        require(state == GeneratorState.JOINED || state == GeneratorState.WIP, Error.ASSIGN_ONLY_TO_IDLE_GENERATORS);

        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];

        // requiredCompute <= idleCapacity
        require(info.computeAllocation <= idleCapacity, Error.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE);

        uint256 availableStake = generator.totalStake - generator.stakeLocked;
        require(availableStake >= amountToLock, Error.INSUFFICIENT_STAKE_TO_LOCK);

        generator.stakeLocked += amountToLock;
        generator.computeConsumed += info.computeAllocation;
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

        uint256 computeReleased = info.computeAllocation;
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
