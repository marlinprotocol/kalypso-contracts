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
    using HELPER for bytes;
    using HELPER for bytes32;

    //---------------------------------------- Event start ----------------------------------------//

    event UpdateKey(address indexed user, uint256 indexed keyIndex);
    event RemoveKey(address indexed user, uint256 indexed keyIndex);
    event ImageBlacklisted(bytes32 indexed imageId);

    //---------------------------------------- Event end ----------------------------------------//

    //---------------------------------------- Constant start ----------------------------------------//

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    //---------------------------------------- Constant end ----------------------------------------//

    //---------------------------------------- State Variable start ----------------------------------------//

    mapping(address => mapping(uint256 => bytes)) public pub_key;
    mapping(bytes32 => bool) public blackListedImages;

    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    //---------------------------------------- State Variable start ----------------------------------------//

    //---------------------------------------- Init start ----------------------------------------//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IAttestationVerifier _av) AttestationAutherUpgradeable(_av, HELPER.ACCEPTABLE_ATTESTATION_DELAY) initializer {}

    function initialize(address _admin, EnclaveImage[] calldata _initWhitelistImages) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(MODERATOR_ROLE, DEFAULT_ADMIN_ROLE);

        __AttestationAuther_init_unchained(_initWhitelistImages);
    }

    //---------------------------------------- Init end ----------------------------------------//

    function addProverManager(address _proverManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEY_REGISTER_ROLE, _proverManager);
    }

    /**
     * @notice Ads a new user after verification
     */
    function updatePubkey(
        address _keyOwner,
        uint256 _keyIndex,
        bytes calldata _pubkey,
        bytes calldata _attestationData
    ) external onlyRole(KEY_REGISTER_ROLE) {
        if (_pubkey.length != 64) {
            revert Error.InvalidEnclaveKey();
        }

        pub_key[_keyOwner][_keyIndex] = _pubkey;

        _verifyKeyInternal(_attestationData);

        emit UpdateKey(_keyOwner, _keyIndex);
    }

    /**
     * @notice Verifies a new key against enclave
     */
    function verifyKey(bytes calldata _attestationData) external onlyRole(KEY_REGISTER_ROLE) {
        _verifyKeyInternal(_attestationData);
    }

    /**
     * @notice Whitelist a new image. Called when a market creator creates a new market
     */
    function whitelistImageUsingPcrs(bytes32 _family, bytes calldata _pcrs) external onlyRole(KEY_REGISTER_ROLE) {
        (bytes memory pcr0, bytes memory pcr1, bytes memory pcr2) = abi.decode(_pcrs, (bytes, bytes, bytes));

        _whitelistImageIfNot(_family, pcr0, pcr1, pcr2);
    }

    function _verifyKeyInternal(bytes calldata _data) internal {
        (
            bytes memory attestation,
            bytes memory enclaveKey,
            bytes memory pcr0,
            bytes memory pcr1,
            bytes memory pcr2,
            uint256 timestamp
        ) = abi.decode(_data, (bytes, bytes, bytes, bytes, bytes, uint256));

        bool isVerified = _verifyEnclaveKey(attestation, IAttestationVerifier.Attestation(enclaveKey, pcr0, pcr1, pcr2, timestamp));
        if (!isVerified) {
            revert Error.EnclaveKeyNotVerified();
        }
    }

    function _whitelistImageIfNot(bytes32 _family, bytes memory _pcr0, bytes memory _pcr1, bytes memory _pcr2) internal {
        bytes32 imageId = _pcr0.GET_IMAGE_ID_FROM_PCRS(_pcr1, _pcr2);
        if (!imageId.IS_ENCLAVE()) {
            revert Error.MustBeAnEnclave(imageId);
        }

        if (blackListedImages[imageId]) {
            revert Error.BlacklistedImage(imageId);
        }
        (bytes32 inferredImageId, ) = _whitelistEnclaveImage(EnclaveImage(_pcr0, _pcr1, _pcr2));

        // inferredImage == false && isVerified == x, invalid image, revert
        if (inferredImageId != imageId) {
            revert Error.InferredImageIdIsDifferent();
        }
        _addEnclaveImageToFamily(imageId, _family);
    }

    /**
     * @notice Removes an existing pubkey
     */
    function removePubkey(address _keyOwner, uint256 _keyIndex) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[_keyOwner][_keyIndex];

        emit RemoveKey(_keyOwner, _keyIndex);
    }

    function allowOnlyVerifiedFamily(bytes32 _familyId, address _key) external view {
        return _allowOnlyVerifiedFamily(_key, _familyId);
    }

    function removeEnclaveImageFromFamily(bytes32 _imageId, bytes32 _family) external onlyRole(KEY_REGISTER_ROLE) {
        _removeEnclaveImageFromFamily(_imageId, _family);
    }

    // ---------- SECURITY FEATURE FUNCTIONS ----------- //
    function blacklistImage(bytes32 _imageId) external onlyRole(MODERATOR_ROLE) {
        if (blackListedImages[_imageId]) {
            revert Error.AlreadyABlacklistedImage(_imageId);
        }
        blackListedImages[_imageId] = true;
        emit ImageBlacklisted(_imageId);
        _revokeEnclaveImage(_imageId);
    }

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //---------------------------------------- Override end ----------------------------------------//

}
