// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "lib/risc0-ethereum/contracts/src/IRiscZeroVerifier.sol";

contract AttestationVerifierZK is
    Initializable, // initializer
    ContextUpgradeable, // _msgSender, _msgData
    ERC165Upgradeable, // supportsInterface
    AccessControlUpgradeable, // RBAC
    UUPSUpgradeable, // public upgrade
    IAttestationVerifier // interface
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    // disable all initializers and reinitializers
    // safeguard against takeover of the logic contract
    constructor(address _risc0Verifier) {
        IRISC0_VERIFIER = IRiscZeroVerifier(_risc0Verifier);
        _disableInitializers();
    }

    //-------------------------------- Overrides start --------------------------------//

    error AttestationVerifierCannotRemoveAllAdmins();

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    //-------------------------------- Overrides end --------------------------------//

    //-------------------------------- Initializer start --------------------------------//

    error AttestationVerifierNoImageProvided();
    error AttestationVerifierInitLengthMismatch();
    error AttestationVerifierInvalidAdmin();

    function initialize(EnclaveImage[] memory images, bytes[] memory enclaveKeys, address _admin) external initializer {
        // The images and their enclave keys are whitelisted without verification that enclave keys are created within
        // the enclave. This is to initialize chain of trust and will be replaced with a more robust solution.
        if (!(images.length != 0)) revert AttestationVerifierNoImageProvided();
        if (!(images.length == enclaveKeys.length)) revert AttestationVerifierInitLengthMismatch();
        if (!(_admin != address(0))) revert AttestationVerifierInvalidAdmin();

        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        for (uint i = 0; i < enclaveKeys.length; i++) {
            bytes32 imageId = _whitelistEnclaveImage(images[i]);
            _whitelistEnclaveKey(enclaveKeys[i], imageId);
        }
    }

    //-------------------------------- Initializer start --------------------------------//

    //-------------------------------- Declarations start --------------------------------//

    struct EnclaveImage {
        bytes PCR0;
        bytes PCR1;
        bytes PCR2;
    }

    IRiscZeroVerifier public immutable IRISC0_VERIFIER;
    // ImageId -> image details
    mapping(bytes32 => EnclaveImage) public whitelistedImages;
    // enclaveKey -> ImageId
    mapping(address => bytes32) public verifiedKeys;

    uint256[48] private __gap_1;

    //-------------------------------- Declarations end --------------------------------//

    //-------------------------------- Admin methods start --------------------------------//

    error AttestationVerifierPubkeyLengthInvalid();
    error AttestationVerifierPCRsInvalid();

    error AttestationVerifierImageNotWhitelisted();
    error AttestationVerifierImageAlreadyWhitelisted();
    error AttestationVerifierKeyNotVerified();
    error AttestationVerifierKeyAlreadyVerified();

    event EnclaveImageWhitelisted(bytes32 indexed imageId, bytes PCR0, bytes PCR1, bytes PCR2);
    event EnclaveImageRevoked(bytes32 indexed imageId);
    event EnclaveKeyWhitelisted(bytes indexed enclavePubKey, bytes32 indexed imageId);
    event EnclaveKeyRevoked(bytes indexed enclavePubKey);
    event EnclaveKeyVerified(bytes indexed enclavePubKey, bytes32 indexed imageId);

    function _pubKeyToAddress(bytes memory pubKey) internal pure returns (address) {
        if (!(pubKey.length == 64)) revert AttestationVerifierPubkeyLengthInvalid();

        bytes32 hash = keccak256(pubKey);
        return address(uint160(uint256(hash)));
    }

    function pubKeyToAddress(bytes memory pubKey) public pure returns (address) {
        return _pubKeyToAddress(pubKey);
    }

    function _whitelistEnclaveImage(EnclaveImage memory image) internal returns (bytes32) {
        if (!(image.PCR0.length == 48 && image.PCR1.length == 48 && image.PCR2.length == 48))
            revert AttestationVerifierPCRsInvalid();

        bytes32 imageId = keccak256(abi.encodePacked(image.PCR0, image.PCR1, image.PCR2));
        if (!(whitelistedImages[imageId].PCR0.length == 0)) revert AttestationVerifierImageAlreadyWhitelisted();
        whitelistedImages[imageId] = EnclaveImage(image.PCR0, image.PCR1, image.PCR2);
        emit EnclaveImageWhitelisted(imageId, image.PCR0, image.PCR1, image.PCR2);
        return imageId;
    }

    function _revokeEnclaveImage(bytes32 imageId) internal {
        if (!(whitelistedImages[imageId].PCR0.length != 0)) revert AttestationVerifierImageNotWhitelisted();
        delete whitelistedImages[imageId];
        emit EnclaveImageRevoked(imageId);
    }

    function _whitelistEnclaveKey(bytes memory enclavePubKey, bytes32 imageId) internal {
        if (!(whitelistedImages[imageId].PCR0.length != 0)) revert AttestationVerifierImageNotWhitelisted();
        address enclaveKey = _pubKeyToAddress(enclavePubKey);
        if (!(verifiedKeys[enclaveKey] == bytes32(0))) revert AttestationVerifierKeyAlreadyVerified();
        verifiedKeys[enclaveKey] = imageId;
        emit EnclaveKeyWhitelisted(enclavePubKey, imageId);
    }

    function _revokeEnclaveKey(bytes memory enclavePubKey) internal {
        address enclaveKey = _pubKeyToAddress(enclavePubKey);
        if (!(verifiedKeys[enclaveKey] != bytes32(0))) revert AttestationVerifierKeyNotVerified();
        delete verifiedKeys[enclaveKey];
        emit EnclaveKeyRevoked(enclavePubKey);
    }

    function whitelistEnclaveImage(
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whitelistEnclaveImage(EnclaveImage(PCR0, PCR1, PCR2));
    }

    function revokeEnclaveImage(bytes32 imageId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        return _revokeEnclaveImage(imageId);
    }

    function whitelistEnclaveKey(bytes memory enclavePubKey, bytes32 imageId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        return _whitelistEnclaveKey(enclavePubKey, imageId);
    }

    function revokeEnclaveKey(bytes memory enclavePubKey) external onlyRole(DEFAULT_ADMIN_ROLE) {
        return _revokeEnclaveKey(enclavePubKey);
    }

    //-------------------------------- Admin methods end --------------------------------//

    //-------------------------------- Open methods start -------------------------------//

    uint256 public constant MAX_AGE = 300;

    error AttestationVerifierAttestationTooOld();

    function _verifyEnclaveKey(bytes memory signature, IAttestationVerifier.Attestation memory attestation) internal {
        if (!(attestation.timestampInMilliseconds / 1000 > block.timestamp - MAX_AGE))
            revert AttestationVerifierAttestationTooOld();
        bytes32 imageId = keccak256(abi.encodePacked(attestation.PCR0, attestation.PCR1, attestation.PCR2));
        if (!(whitelistedImages[imageId].PCR0.length != 0)) revert AttestationVerifierImageNotWhitelisted();

        address enclaveKey = pubKeyToAddress(attestation.enclavePubKey);
        if (!(verifiedKeys[enclaveKey] == bytes32(0))) revert AttestationVerifierKeyAlreadyVerified();

        _verify(signature, attestation);

        verifiedKeys[enclaveKey] = imageId;
        emit EnclaveKeyVerified(attestation.enclavePubKey, imageId);
    }

    function verifyEnclaveKey(bytes memory signature, Attestation memory attestation) external {
        return _verifyEnclaveKey(signature, attestation);
    }

    //-------------------------------- Open methods end -------------------------------//

    //-------------------------------- Read only methods start -------------------------------//

    bytes32 private constant DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version)"),
                keccak256("marlin.oyster.AttestationVerifier"),
                keccak256("1")
            )
        );

    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(bytes enclavePubKey,bytes PCR0,bytes PCR1,bytes PCR2,uint256 timestampInMilliseconds)");

    function _verify(bytes memory signature, Attestation memory attestation) internal view {
        bytes32 hashStruct = keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                keccak256(attestation.enclavePubKey),
                keccak256(attestation.PCR0),
                keccak256(attestation.PCR1),
                keccak256(attestation.PCR2),
                attestation.timestampInMilliseconds
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));

        address signer = ECDSA.recover(digest, signature);
        bytes32 imageId = verifiedKeys[signer];

        (bytes memory seal, bytes32 guestId, bytes32 journalDigest) = abi.decode(signature, (bytes, bytes32, bytes32));
        IRISC0_VERIFIER.verify(seal, guestId, journalDigest);

        if (!(imageId != bytes32(0))) revert AttestationVerifierKeyNotVerified();
        if (!(whitelistedImages[imageId].PCR0.length != 0)) revert AttestationVerifierImageNotWhitelisted();
    }

    function verify(bytes memory signature, Attestation memory attestation) external view {
        _verify(signature, attestation);
    }

    function verify(bytes memory data) external view {
        (bytes memory signature, Attestation memory attestation) = abi.decode(data, (bytes, Attestation));
        _verify(signature, attestation);
    }

    //-------------------------------- Read only methods end -------------------------------//
}