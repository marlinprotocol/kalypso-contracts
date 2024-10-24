// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "../periphery/risc0/interfaces/RiscZeroVerifierEmergencyStop.sol";


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
        RISC0_VERIFIER = RiscZeroVerifierEmergencyStop(_risc0Verifier);
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
    }
    struct EnclaveImage {
        bytes PCR0;
        bytes PCR1;
        bytes PCR2;
    }

    RiscZeroVerifierEmergencyStop public immutable RISC0_VERIFIER;

    uint256[50] private __gap_1;

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


    //-------------------------------- Admin methods end --------------------------------//

    //-------------------------------- Open methods start -------------------------------//

    uint256 public constant MAX_AGE = 300;

    error AttestationVerifierAttestationTooOld(); 

    function _verify(bytes memory proof, Attestation memory attestation) internal view {
        (bytes memory seal, bytes32 imageId, bytes memory journal) = abi.decode(proof, (bytes, bytes32, bytes));

        // Use RISC0_VERIFIER to check if the receipt is right, else revert
        RISC0_VERIFIER.verify(seal, imageId, sha256(journal));

        this._validateProofAndAttestation(journal, attestation);
    }

    function _validateProofAndAttestation(bytes calldata journal, Attestation memory attestation) public view {
        if(!
        (
            (sha256(journal[8:56]) == sha256(attestation.PCR0)) && 
            (sha256(journal[56:104]) == sha256(attestation.PCR1)) && 
            (sha256(journal[104:152]) == sha256(attestation.PCR2)) && 
            (sha256(journal[249:313]) == sha256(attestation.enclavePubKey))
            )
        ) revert AttestationVerifierAttestationTooOld();
    }

    // using bytes memory proof instead of Receipt memory receipt, because interface demands so
    function verify(bytes memory proof, Attestation memory attestation) external view {
        _verify(proof, attestation);
    }

    function verify(bytes memory data) external view {
        (bytes memory proof, Attestation memory attestation) = abi.decode(data, (bytes, Attestation));
        _verify(proof, attestation);
    }

    //-------------------------------- Read only methods end -------------------------------//
}