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
    uint256 public immutable stakingAmount;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable slashingPenalty;

    bytes32 public constant SLASHER_ROLE = bytes32(uint256(keccak256("slasher")) - 1);
    //-------------------------------- Constants and Immutable start --------------------------------//

    //-------------------------------- State variables start --------------------------------//
    mapping(address => mapping(bytes32 => GeneratorWithState)) public generatorRegistry;

    IProofMarketPlace public proofMarketPlace;

    //-------------------------------- State variables end --------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _stakingToken, uint256 _stakingAmount, uint256 _slashingPenalty) {
        stakingToken = _stakingToken;
        stakingAmount = _stakingAmount;
        slashingPenalty = _slashingPenalty;
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

    function register(Generator calldata generator, bytes32 marketId) external override {
        address verifierAddress = proofMarketPlace.getMarketVerifier(marketId);

        require(verifierAddress != address(0), Error.CANNOT_BE_ZERO);
        address _msgSender = _msgSender();
        stakingToken.safeTransferFrom(_msgSender, address(this), stakingAmount);

        require(generatorRegistry[_msgSender][marketId].generator.generatorData.length == 0, Error.ALREADY_EXISTS);
        require(generator.rewardAddress != address(0), Error.CANNOT_BE_ZERO);
        generatorRegistry[_msgSender][marketId] = GeneratorWithState(
            GeneratorState.JOINED,
            Generator(generator.rewardAddress, generator.generatorData, stakingAmount)
        );

        emit RegisteredGenerator(_msgSender, marketId);
    }

    // Todo: Optimise this
    function getGeneratorState(address _generator, bytes32 marketId) public view returns (GeneratorState) {
        GeneratorWithState memory generatorWithState = generatorRegistry[_generator][marketId];

        if (
            generatorWithState.state == GeneratorState.NULL ||
            generatorWithState.state == GeneratorState.WIP ||
            generatorWithState.state == GeneratorState.REQUESTED_FOR_EXIT
        ) {
            return generatorWithState.state;
        }

        // Once generator is joined and active
        if (generatorWithState.state == GeneratorState.JOINED) {
            if (generatorWithState.generator.amountLocked > slashingPenalty) {
                return GeneratorState.JOINED;
            } else {
                return GeneratorState.LOW_STAKE;
            }
        }

        return GeneratorState.NULL;
    }

    function deregister(bytes32 marketId) external override {
        address _msgSender = _msgSender();
        GeneratorState state = getGeneratorState(_msgSender, marketId);

        if (state == GeneratorState.WIP) {
            generatorRegistry[_msgSender][marketId].state = GeneratorState.REQUESTED_FOR_EXIT;
            return;
        }

        require(state != GeneratorState.WIP && state != GeneratorState.REQUESTED_FOR_EXIT, Error.HAS_A_PENDING_WORK);
        require(state != GeneratorState.NULL, Error.CANNOT_BE_ZERO);

        GeneratorWithState memory generatorWithState = generatorRegistry[_msgSender][marketId];
        stakingToken.safeTransfer(
            generatorWithState.generator.rewardAddress,
            generatorWithState.generator.amountLocked
        );

        delete generatorRegistry[_msgSender][marketId];
        emit DeregisteredGenerator(_msgSender, marketId);
    }

    function getGeneratorRewardAddress(address _generator, bytes32 marketId) public view override returns (address) {
        return generatorRegistry[_generator][marketId].generator.rewardAddress;
    }

    // TODO: current _rewardAddress gets all the slash, slashing economics not implemented
    // returns slashed amount
    function slashGenerator(
        address _generator,
        bytes32 marketId,
        address _rewardAddress
    ) external onlyRole(SLASHER_ROLE) returns (uint256) {
        generatorRegistry[_generator][marketId].generator.amountLocked -= slashingPenalty;
        stakingToken.safeTransfer(_rewardAddress, slashingPenalty);
        return slashingPenalty;
    }

    function addStash(address _generator, bytes32 marketId, uint256 _amount) external {
        stakingToken.safeTransferFrom(_msgSender(), address(this), _amount);
        GeneratorState state = getGeneratorState(_generator, marketId);

        require(state == GeneratorState.JOINED || state == GeneratorState.JOINED, Error.INVALID_GENERATOR);
        generatorRegistry[_generator][marketId].generator.amountLocked += _amount;

        emit AddExtraStash(_generator, _amount);
    }
}
