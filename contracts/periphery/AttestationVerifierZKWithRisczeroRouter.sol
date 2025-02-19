// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "../periphery/risc0/interfaces/IRiscZeroVerifier.sol";

contract AttestationProofVerifier is
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
        RISC0_VERIFIER = IRiscZeroVerifier(_risc0Verifier);
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
    error AttestationVerifierNotImplemented();

    function initialize(address _admin) external initializer {
        if (!(_admin != address(0))) revert AttestationVerifierInvalidAdmin();

        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }
    
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRiscZeroVerifier public immutable RISC0_VERIFIER;

    uint256[50] private __gap_1;

    //-------------------------------- Declarations end --------------------------------//

    //-------------------------------- Admin methods start --------------------------------//

    error AttestationVerifierPubkeyLengthInvalid();
    error AttestationVerifierPCRsInvalid();

    error AttestationVerifierImageNotWhitelisted();
    error AttestationVerifierImageAlreadyWhitelisted();
    error AttestationVerifierKeyNotVerified();
    error AttestationVerifierKeyAlreadyVerified();

    event EnclaveKeyWhitelisted(bytes indexed enclavePubKey, bytes32 indexed imageId);
    event EnclaveKeyRevoked(bytes indexed enclavePubKey);
    event EnclaveKeyVerified(bytes indexed enclavePubKey, bytes32 indexed imageId);


    //-------------------------------- Admin methods end --------------------------------//

    //-------------------------------- Open methods start -------------------------------//

    uint256 public constant MAX_AGE = 300;

    error AttestationVerifierAttestationTooOld(); 

    function _verify(bytes memory proof, bytes memory attestation) internal view {
        (bytes memory seal, bytes32 imageId, bytes memory journal) = abi.decode(proof, (bytes, bytes32, bytes));

        // Check if seal has at least 4 bytes to compare prefixes
        if (seal.length >= 4) {
            // Extract the first 4 bytes (prefix) of the seal
            bytes4 prefix;
            assembly {
                // Load the first 32 bytes from seal, then shift to get the first 4 bytes
                prefix := mload(add(seal, 32))
            }

            // Define the prefixes to check against
            bytes4 prefix1 = 0x310fe598;
            bytes4 prefix2 = 0x50bd1769;
            bytes4 newPrefix = 0xc101b42b;

            // Check if the prefix matches either of the specified prefixes
            if (prefix == prefix1 || prefix == prefix2) {
                // Create a new seal with the new prefix
                bytes memory newSeal = new bytes(seal.length);

                // Replace the first 4 bytes with the new prefix
                assembly {
                    // Store the new prefix at the beginning of newSeal
                    mstore(add(newSeal, 32), shl(224, newPrefix))
                }

                // Copy the remaining bytes from the original seal to the new seal
                for (uint i = 4; i < seal.length; i++) {
                    newSeal[i] = seal[i];
                }

                // Update the seal variable to the new seal
                seal = newSeal;
            }
        }
        
        // Use RISC0_VERIFIER to check if the receipt is right, else revert
        RISC0_VERIFIER.verify(seal, imageId, sha256(journal));

        this._validateProofAndAttestation(journal, attestation);
    }

    function _validateProofAndAttestation(bytes calldata journal, bytes calldata attestation) public pure {
        if(!
        (
            (sha256(journal[:8]) == sha256(attestation[87:95])) && // Checking timestamp
            (sha256(journal[8:56]) == sha256(attestation[104:152])) && // Checking PCR0
            (sha256(journal[56:104]) == sha256(attestation[155:203])) && // Checking PCR1
            (sha256(journal[104:152]) == sha256(attestation[206:254])) // Checking PCR2
            )
        ) revert AttestationVerifierAttestationTooOld();
    }

    // using bytes memory proof instead of Receipt memory receipt, because interface demands so
    function verify(bytes memory, Attestation memory) external pure {
        revert AttestationVerifierNotImplemented();
    }

    function verify(bytes memory data) external view {
        (bytes memory proof, bytes memory attestation) = abi.decode(data, (bytes, bytes));
        _verify(proof, attestation);
    }

    //-------------------------------- Read only methods end -------------------------------//
}