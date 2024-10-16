// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IAttestationVerifier.sol";

contract AttestationAutherUpgradeable is
    Initializable // initializer
{
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IAttestationVerifier public immutable ATTESTATION_VERIFIER;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 public immutable ATTESTATION_MAX_AGE;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IAttestationVerifier attestationVerifier, uint256 maxAge) {
        ATTESTATION_VERIFIER = attestationVerifier;
        ATTESTATION_MAX_AGE = maxAge;
    }

    struct EnclaveImage {
        bytes PCR0;
        bytes PCR1;
        bytes PCR2;
    }

    /// @custom:storage-location erc7201:marlin.oyster.storage.AttestationAuther
    struct AttestationAutherStorage {
        mapping(bytes32 => EnclaveImage) whitelistedImages;
        mapping(address => bytes32) verifiedKeys;
        mapping(bytes32 => mapping(bytes32 => bool)) imageFamilies;
    }

    // keccak256(abi.encode(uint256(keccak256("marlin.oyster.storage.AttestationAuther")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AttestationAutherStorageLocation =
        0xc17b4b708b6f44255c20913a9d97a05300b670342c71fe5ae5b617bd4db55000;

    function _getAttestationAutherStorage() private pure returns (AttestationAutherStorage storage $) {
        assembly {
            $.slot := AttestationAutherStorageLocation
        }
    }

    error AttestationAutherPubkeyLengthInvalid();
    error AttestationAutherPCRsInvalid();
    error AttestationAutherImageNotWhitelisted();
    error AttestationAutherImageNotInFamily();
    error AttestationAutherKeyNotVerified();
    error AttestationAutherAttestationTooOld();
    error AttestationAutherMismatchedLengths();

    event EnclaveImageWhitelisted(bytes32 indexed imageId, bytes PCR0, bytes PCR1, bytes PCR2);
    event EnclaveImageRevoked(bytes32 indexed imageId);
    event EnclaveImageAddedToFamily(bytes32 indexed imageId, bytes32 family);
    event EnclaveImageRemovedFromFamily(bytes32 indexed imageId, bytes32 family);
    event EnclaveKeyWhitelisted(bytes indexed enclavePubKey, bytes32 indexed imageId);
    event EnclaveKeyRevoked(bytes indexed enclavePubKey);
    event EnclaveKeyVerified(bytes indexed enclavePubKey, bytes32 indexed imageId);

    function __AttestationAuther_init_unchained(EnclaveImage[] memory images) internal onlyInitializing {
        for (uint256 i = 0; i < images.length; i++) {
            _whitelistEnclaveImage(images[i]);
        }
    }

    function __AttestationAuther_init_unchained(
        EnclaveImage[] memory images,
        bytes32[] memory families
    ) internal onlyInitializing {
        if (!(images.length == families.length)) revert AttestationAutherMismatchedLengths();
        for (uint256 i = 0; i < images.length; i++) {
            (bytes32 imageId,) = _whitelistEnclaveImage(images[i]);
            _addEnclaveImageToFamily(imageId, families[i]);
        }
    }

    function _pubKeyToAddress(bytes memory pubKey) internal pure returns (address) {
        if (!(pubKey.length == 64)) revert AttestationAutherPubkeyLengthInvalid();

        bytes32 hash = keccak256(pubKey);
        return address(uint160(uint256(hash)));
    }

    function _whitelistEnclaveImage(EnclaveImage memory image) internal virtual returns (bytes32, bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        if (!(image.PCR0.length == 48 && image.PCR1.length == 48 && image.PCR2.length == 48))
            revert AttestationAutherPCRsInvalid();

        bytes32 imageId = keccak256(abi.encodePacked(image.PCR0, image.PCR1, image.PCR2));
        if (!($.whitelistedImages[imageId].PCR0.length == 0)) return (imageId, false);

        $.whitelistedImages[imageId] = EnclaveImage(image.PCR0, image.PCR1, image.PCR2);
        emit EnclaveImageWhitelisted(imageId, image.PCR0, image.PCR1, image.PCR2);

        return (imageId, true);
    }

    function _revokeEnclaveImage(bytes32 imageId) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        if (!($.whitelistedImages[imageId].PCR0.length != 0)) return false;

        delete $.whitelistedImages[imageId];
        emit EnclaveImageRevoked(imageId);

        return true;
    }

    function _addEnclaveImageToFamily(bytes32 imageId, bytes32 family) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        if (!($.imageFamilies[family][imageId] == false)) return false;

        $.imageFamilies[family][imageId] = true;
        emit EnclaveImageAddedToFamily(imageId, family);

        return true;
    }

    function _removeEnclaveImageFromFamily(bytes32 imageId, bytes32 family) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        if (!($.imageFamilies[family][imageId] == true)) return false;

        $.imageFamilies[family][imageId] = false;
        emit EnclaveImageRemovedFromFamily(imageId, family);

        return true;
    }

    function _whitelistEnclaveKey(bytes memory enclavePubKey, bytes32 imageId) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();

        address enclaveKey = _pubKeyToAddress(enclavePubKey);
        if (!($.verifiedKeys[enclaveKey] == bytes32(0))) return false;

        $.verifiedKeys[enclaveKey] = imageId;
        emit EnclaveKeyWhitelisted(enclavePubKey, imageId);

        return true;
    }

    function _revokeEnclaveKey(bytes memory enclavePubKey) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        address enclaveKey = _pubKeyToAddress(enclavePubKey);
        if (!($.verifiedKeys[enclaveKey] != bytes32(0))) return false;

        delete $.verifiedKeys[enclaveKey];
        emit EnclaveKeyRevoked(enclavePubKey);

        return true;
    }

    function _verifyEnclaveKey(bytes memory signature, IAttestationVerifier.Attestation memory attestation) internal virtual returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        bytes32 imageId = keccak256(abi.encodePacked(attestation.PCR0, attestation.PCR1, attestation.PCR2));
        if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
        if (!(attestation.timestampInMilliseconds / 1000 > block.timestamp - ATTESTATION_MAX_AGE))
            revert AttestationAutherAttestationTooOld();

        ATTESTATION_VERIFIER.verify(signature, attestation);

        address enclaveKey = _pubKeyToAddress(attestation.enclavePubKey);
        if (!($.verifiedKeys[enclaveKey] == bytes32(0))) return false;

        $.verifiedKeys[enclaveKey] = imageId;
        emit EnclaveKeyVerified(attestation.enclavePubKey, imageId);

        return true;
    }

    function verifyEnclaveKey(bytes memory signature, IAttestationVerifier.Attestation memory attestation) external returns (bool) {
        return _verifyEnclaveKey(signature, attestation);
    }

    function _allowOnlyVerified(address key) internal virtual view {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        bytes32 imageId = $.verifiedKeys[key];
        if (!(imageId != bytes32(0))) revert AttestationAutherKeyNotVerified();
        if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
    }

    function _allowOnlyVerifiedFamily(address key, bytes32 family) internal virtual view {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        bytes32 imageId = $.verifiedKeys[key];
        if (!(imageId != bytes32(0))) revert AttestationAutherKeyNotVerified();
        if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
        if (!($.imageFamilies[family][imageId])) revert AttestationAutherImageNotInFamily();
    }

    function getWhitelistedImage(bytes32 _imageId) external view returns (EnclaveImage memory) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        return $.whitelistedImages[_imageId];
    }

    function getVerifiedKey(address _key) external view returns (bytes32) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        return $.verifiedKeys[_key];
    }

    function isImageInFamily(bytes32 imageId, bytes32 family) external view returns (bool) {
        AttestationAutherStorage storage $ = _getAttestationAutherStorage();

        return $.imageFamilies[family][imageId];
    }
}