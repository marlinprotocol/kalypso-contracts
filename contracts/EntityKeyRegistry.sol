// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "./periphery/AttestationAutherUpgradeable.sol";

import "./lib/Error.sol";
import "./lib/Helper.sol";

contract EntityKeyRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    AttestationAutherUpgradeable
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IAttestationVerifier _av
    ) AttestationAutherUpgradeable(_av, HELPER.ACCEPTABLE_ATTESTATION_DELAY) initializer {}

    using HELPER for bytes;
    using HELPER for bytes32;

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");

    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    mapping(address => mapping(uint256 => bytes)) public pub_key;

    mapping(bytes32 => bool) public blackListedImages;

    event UpdateKey(address indexed user, uint256 indexed keyIndex);
    event RemoveKey(address indexed user, uint256 indexed keyIndex);

    event ImageBlacklisted(bytes32 indexed imageId);

    function initialize(address _admin, EnclaveImage[] memory initWhitelistImages) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(MODERATOR_ROLE, DEFAULT_ADMIN_ROLE);

        __AttestationAuther_init_unchained(initWhitelistImages);
    }

    function addGeneratorRegistry(address _generatorRegistry) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEY_REGISTER_ROLE, _generatorRegistry);
    }

    /**
     * @notice Ads a new user after verification
     */
    function updatePubkey(
        address keyOwner,
        uint256 keyIndex,
        bytes calldata pubkey,
        bytes calldata attestation_data
    ) external onlyRole(KEY_REGISTER_ROLE) {
        if (pubkey.length != 64) {
            revert Error.InvalidEnclaveKey();
        }

        pub_key[keyOwner][keyIndex] = pubkey;

        _verifyKeyInternal(attestation_data);

        emit UpdateKey(keyOwner, keyIndex);
    }

    /**
     * @notice Verifies a new key against enclave
     */
    function verifyKey(bytes calldata attestation_data) external onlyRole(KEY_REGISTER_ROLE) {
        _verifyKeyInternal(attestation_data);
    }

    /**
     * @notice Whitelist a new image. Called when a market creator creates a new market
     */
    function whitelistImageUsingPcrs(bytes32 family, bytes calldata pcrs) external onlyRole(KEY_REGISTER_ROLE) {
        (bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) = abi.decode(pcrs, (bytes, bytes, bytes));

        _whitelistImageIfNot(family, PCR0, PCR1, PCR2);
    }

    function _verifyKeyInternal(bytes calldata data) internal {
        (
            bytes memory attestation,
            bytes memory enclaveKey,
            bytes memory PCR0,
            bytes memory PCR1,
            bytes memory PCR2,
            uint256 timestamp
        ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256));

        // compute image id in proper way
        _verifyEnclaveKey(attestation, IAttestationVerifier.Attestation(enclaveKey, PCR0, PCR1, PCR2, timestamp));
    }

    function _whitelistImageIfNot(bytes32 family, bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) internal {
        bytes32 imageId = PCR0.GET_IMAGE_ID_FROM_PCRS(PCR1, PCR2);
        if (!imageId.IS_ENCLAVE()) {
            revert Error.MustBeAnEnclave(imageId);
        }

        if (blackListedImages[imageId]) {
            revert Error.BlacklistedImage(imageId);
        }
        _whitelistEnclaveImage(EnclaveImage(PCR0, PCR1, PCR2));
        _addEnclaveImageToFamily(imageId, family);
    }

    /**
     * @notice Removes an existing pubkey
     */
    function removePubkey(address keyOwner, uint256 keyIndex) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[keyOwner][keyIndex];

        emit RemoveKey(keyOwner, keyIndex);
    }

    function allowOnlyVerifiedFamily(bytes32 familyId, address _key) external view {
        return _allowOnlyVerifiedFamily(_key, familyId);
    }

    // ---------- SECURITY FEATURE FUNCTIONS ----------- //
    function blacklistImage(bytes32 imageId) external onlyRole(MODERATOR_ROLE) {
        if (blackListedImages[imageId]) {
            revert Error.AlreadyABlacklistedImage(imageId);
        }
        blackListedImages[imageId] = true;
        emit ImageBlacklisted(imageId);
        _revokeEnclaveImage(imageId);
    }

    function removeEnclaveImageFromFamily(bytes32 imageId, bytes32 family) external onlyRole(MODERATOR_ROLE) {
        _removeEnclaveImageFromFamily(imageId, family);
    }

    // for further increase
    uint256[50] private __gap1_0;
}
