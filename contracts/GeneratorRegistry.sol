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

import "./interfaces/IProofMarketPlace.sol";

import "./interfaces/IGeneratorRegsitry.sol";
import "./lib/Error.sol";

// import "hardhat/console.sol";

contract GeneratorRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    IGeneratorRegistry
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

    function _authorizeUpgrade(address /*account*/) internal view override onlyAdmin {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Constants and Immutable start --------------------------------//
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable stakingToken;

    bytes32 public constant SLASHER_ROLE = bytes32(uint256(keccak256("slasher")) - 1);

    uint256 public constant PARALLEL_REQUESTS_UPPER_LIMIT = 100;

    uint256 private constant EXPONENT = 10e18;
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => Generator) public generatorRegistry;
    mapping(address => mapping(bytes32 => GeneratorInfoPerMarket)) public generatorInfoPerMarket;

    IProofMarketPlace public proofMarketPlace;

    //-------------------------------- State variables end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _stakingToken) {
        stakingToken = _stakingToken;
    }

    function initialize(address _admin, address _proofMarketPlace) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SLASHER_ROLE, _proofMarketPlace);
        proofMarketPlace = IProofMarketPlace(_proofMarketPlace);
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Error.ONLY_ADMIN_CAN_CALL);
        _;
    }

    function register(address rewardAddress, uint256 declaredCompute, bytes memory generatorData) external override {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generatorData.length != 0, Error.CANNOT_BE_ZERO);
        require(rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        require(declaredCompute != 0, Error.CANNOT_BE_ZERO);

        require(generator.generatorData.length == 0, Error.GENERATOR_ALREADY_EXISTS);
        require(generator.rewardAddress == address(0), Error.GENERATOR_ALREADY_EXISTS);

        generatorRegistry[_msgSender] = Generator(rewardAddress, 0, 0, 0, 0, 0, declaredCompute, generatorData);

        emit RegisteredGenerator(_msgSender);
    }

    function deregister(address refundAddress) external override {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generator.totalCompute == 0, Error.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET);
        stakingToken.safeTransfer(refundAddress, generator.totalStake);
        delete generatorRegistry[_msgSender];

        emit DeregisteredGenerator(_msgSender);
    }

    function stake(address generatorAddress, uint256 amount) external override returns (uint256) {
        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);
        require(amount != 0, Error.CANNOT_BE_ZERO);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        generator.totalStake += amount;

        emit AddedStash(generatorAddress, amount);
        return generator.totalStake;
    }

    function unstake(address receipient, uint256 amount) external override returns (uint256) {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];

        uint256 availableAmount = generator.totalStake - generator.stakeLocked;
        require(amount <= availableAmount, Error.CAN_NOT_WITHDRAW_MORE_UNLOCKED_AMOUNT);

        generator.totalStake -= amount;
        stakingToken.safeTransfer(receipient, amount);

        emit RemovedStash(generatorAddress, amount);
        return generator.totalStake;
    }

    function joinMarketPlace(
        bytes32 marketId,
        uint256 computeAllocation,
        uint256 proofGenerationCost,
        uint256 proposedTime
    ) external {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);

        require(proofMarketPlace.verifier(marketId) != address(0), Error.INVALID_MARKET);
        require(info.state == GeneratorState.NULL, Error.ALREADY_JOINED_MARKET);

        require(proposedTime != 0, Error.CANNOT_BE_ZERO);
        require(computeAllocation != 0, Error.CANNOT_BE_ZERO);

        generator.totalCompute += computeAllocation;
        require(generator.totalCompute <= generator.declaredCompute, Error.CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE);
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
        bytes32 marketId
    ) public view override returns (GeneratorState, uint256) {
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

    function leaveMarketPlaces(bytes32[] calldata marketIds) external override {
        for (uint256 index = 0; index < marketIds.length; index++) {
            _leaveMarketPlace(marketIds[index]);
        }
    }

    function leaveMarketPlace(bytes32 marketId) external {
        _leaveMarketPlace(marketId);
    }

    function _leaveMarketPlace(bytes32 marketId) internal {
        require(proofMarketPlace.verifier(marketId) != address(0), Error.INVALID_MARKET);

        address generatorAddress = msg.sender;
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        require(info.activeRequests == 0, Error.CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST);

        Generator storage generator = generatorRegistry[generatorAddress];
        generator.totalCompute -= info.computeAllocation;

        delete generatorInfoPerMarket[generatorAddress][marketId];
        emit LeftMarketplace(generatorAddress, marketId);
    }

    function slashGenerator(
        address generatorAddress,
        bytes32 marketId,
        uint256 slashingAmount,
        address rewardAddress
    ) external override onlyRole(SLASHER_ROLE) returns (uint256) {
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

        stakingToken.safeTransfer(rewardAddress, slashingAmount);

        return generator.totalStake;
    }

    function assignGeneratorTask(
        address generatorAddress,
        bytes32 marketId,
        uint256 amountToLock
    ) external override onlyRole(SLASHER_ROLE) {
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
        bytes32 marketId,
        uint256 stakeToRelease
    ) external override onlyRole(SLASHER_ROLE) {
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
        bytes32 marketId
    ) public view override returns (uint256, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        return (info.proofGenerationCost, info.proposedTime);
    }

    function getGeneratorRewardDetails(
        address generatorAddress,
        bytes32 marketId
    ) public view override returns (address, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        Generator memory generator = generatorRegistry[generatorAddress];

        return (generator.rewardAddress, info.proofGenerationCost);
    }
}
