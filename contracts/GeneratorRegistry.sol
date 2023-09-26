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

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable minStakingAmount;

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
    constructor(IERC20Upgradeable _stakingToken, uint256 _stakingAmount) {
        stakingToken = _stakingToken;
        minStakingAmount = _stakingAmount;
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

    function register(address rewardAddress, bytes memory generatorData) external override {
        address _msgSender = msg.sender;
        Generator memory generator = generatorRegistry[_msgSender];

        require(generatorData.length != 0, Error.CANNOT_BE_ZERO);
        require(rewardAddress != address(0), Error.CANNOT_BE_ZERO);

        require(generator.generatorData.length == 0, Error.ALREADY_EXISTS);
        require(generator.rewardAddress == address(0), Error.ALREADY_EXISTS);

        generatorRegistry[_msgSender] = Generator(rewardAddress, 0, 0, generatorData);

        emit RegisteredGenerator(_msgSender);
    }

    function deregister(address refundAddress) external override {
        address _msgSender = msg.sender;

        require(generatorRegistry[_msgSender].numberOfSupportedMarkets == 0, Error.SHOULD_BE_ZERO);
        stakingToken.safeTransfer(refundAddress, generatorRegistry[_msgSender].totalStake);

        delete generatorRegistry[_msgSender];

        emit DeregisteredGenerator(_msgSender);
    }

    function stake(address generatorAddress, uint256 amount) external {
        Generator storage generator = generatorRegistry[generatorAddress];
        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        generator.totalStake += amount;

        emit AddedStash(generatorAddress, amount);
    }

    function joinMarketPlace(
        bytes32 marketId,
        uint256 proofGenerationCost,
        uint256 proposedTime,
        uint256 maxParallelRequestsSupported
    ) external {
        address generatorAddress = msg.sender;
        Generator storage generator = generatorRegistry[generatorAddress];
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];

        require(generator.generatorData.length != 0, Error.INVALID_GENERATOR);
        require(generator.rewardAddress != address(0), Error.INVALID_GENERATOR);

        require(proofMarketPlace.verifier(marketId) != address(0), Error.DOES_NOT_EXISTS);
        require(info.state == GeneratorState.NULL, Error.ALREADY_EXISTS);

        require(proposedTime != 0, Error.CANNOT_BE_ZERO);
        require(maxParallelRequestsSupported <= PARALLEL_REQUESTS_UPPER_LIMIT, Error.SHOULD_BE_LESS_THAN_OR_EQUAL);

        require(generator.totalStake >= proofMarketPlace.minStakeToJoin(marketId), Error.INSUFFICIENT_STAKE);

        generatorInfoPerMarket[generatorAddress][marketId] = GeneratorInfoPerMarket(
            GeneratorState.JOINED,
            proofGenerationCost,
            proposedTime,
            maxParallelRequestsSupported,
            0
        );
        generator.numberOfSupportedMarkets++;
        emit JoinedMarketPlace(generatorAddress, marketId);
    }

    function getGeneratorState(
        address generatorAddress,
        bytes32 marketId
    ) public view returns (GeneratorState, uint256) {
        GeneratorInfoPerMarket memory info = generatorInfoPerMarket[generatorAddress][marketId];
        Generator memory generator = generatorRegistry[generatorAddress];

        if (info.state == GeneratorState.REQUESTED_FOR_EXIT) {
            return (info.state, 0);
        }

        if (info.state != GeneratorState.NULL && generator.totalStake < minStakingAmount) {
            return (GeneratorState.LOW_STAKE, 0);
        }

        if (info.state == GeneratorState.JOINED) {
            return (GeneratorState.WIP, info.maxParallelRequestsSupported);
        }

        if (info.state == GeneratorState.WIP) {
            uint256 idleCapacity = info.maxParallelRequestsSupported - info.currentActiveRequest;
            return (GeneratorState.WIP, idleCapacity);
        }

        return (GeneratorState.NULL, 0);
    }

    function leaveMarketPlace(bytes32 marketId) external override {
        require(proofMarketPlace.verifier(marketId) != address(0), Error.DOES_NOT_EXISTS);

        address generatorAddress = msg.sender;
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);

        require(state != GeneratorState.NULL, Error.INVALID_GENERATOR);

        if (state == GeneratorState.WIP) {
            generatorInfoPerMarket[generatorAddress][marketId].state = GeneratorState.REQUESTED_FOR_EXIT;
            emit RequestExitMarketPlace(generatorAddress, marketId);
            return;
        }

        require(state == GeneratorState.JOINED || state == GeneratorState.REQUESTED_FOR_EXIT, Error.HAS_A_PENDING_WORK);
        require(generatorInfoPerMarket[generatorAddress][marketId].currentActiveRequest == 0, Error.SHOULD_BE_ZERO);

        generatorRegistry[generatorAddress].numberOfSupportedMarkets--; // will throw underflow if no market is supported

        delete generatorInfoPerMarket[generatorAddress][marketId];
        emit LeftMarketplace(generatorAddress, marketId);
    }

    function slashGenerator(
        address generatorAddress,
        bytes32 marketId,
        address rewardAddress
    ) external override onlyRole(SLASHER_ROLE) returns (uint256) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);
        require(state == GeneratorState.WIP || state == GeneratorState.REQUESTED_FOR_EXIT, Error.CAN_N0T_BE_SLASHED);

        uint256 proofGenerationCost = generatorInfoPerMarket[generatorAddress][marketId].proofGenerationCost;

        uint256 slashingPenalty = proofMarketPlace.slashingPenalty(marketId);
        uint256 penalty = (slashingPenalty * proofGenerationCost) / EXPONENT;

        penalty = penalty < generatorRegistry[generatorAddress].totalStake
            ? generatorRegistry[generatorAddress].totalStake
            : penalty;

        generatorRegistry[generatorAddress].totalStake -= penalty;
        stakingToken.safeTransfer(rewardAddress, penalty);

        return penalty;
    }

    function assignGeneratorTask(address generatorAddress, bytes32 marketId) external override onlyRole(SLASHER_ROLE) {
        (GeneratorState state, uint256 idleCapacity) = getGeneratorState(generatorAddress, marketId);
        require(state == GeneratorState.JOINED || state == GeneratorState.WIP, Error.ONLY_TO_IDLE_GENERATORS);

        require(idleCapacity > 0, Error.INSUFFICIENT_GENERATOR_CAPACITY);

        Generator memory generator = generatorRegistry[generatorAddress];

        require(generator.totalStake >= minStakingAmount, Error.INSUFFICIENT_STAKE);

        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];
        info.currentActiveRequest++;
        if (info.state == GeneratorState.JOINED) {
            info.state = GeneratorState.WIP;
        }
    }

    function completeGeneratorTask(
        address generatorAddress,
        bytes32 marketId
    ) external override onlyRole(SLASHER_ROLE) {
        (GeneratorState state, ) = getGeneratorState(generatorAddress, marketId);
        require(
            state == GeneratorState.WIP ||
                state == GeneratorState.REQUESTED_FOR_EXIT ||
                state == GeneratorState.LOW_STAKE,
            Error.ONLY_WORKING_GENERATORS
        );

        GeneratorInfoPerMarket storage info = generatorInfoPerMarket[generatorAddress][marketId];
        info.currentActiveRequest--;
        if (info.currentActiveRequest == 0) {
            info.state = GeneratorState.JOINED;
        }
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
