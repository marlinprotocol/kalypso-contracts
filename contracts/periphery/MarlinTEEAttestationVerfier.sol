// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./Teefetch/Teefetch.sol";
import "hardhat/console.sol";

contract MarlinTEEAttestationVerifier is
    Initializable, // initializer
    ContextUpgradeable, // _msgSender, _msgData
    ERC165Upgradeable, // supportsInterface
    AccessControlUpgradeable, // RBAC
    UUPSUpgradeable, // public upgrade
    IAttestationVerifier // interface
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    event AttestationVerified(bytes signer, bytes seal);

    /// @custom:oz-upgrades-unsafe-allow constructor
    // disable all initializers and reinitializers
    // safeguard against takeover of the logic contract
    constructor(address _teeFetchContract) {
        TEEFETCH_VERIFIER = Teefetch(_teeFetchContract);
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
    Teefetch public immutable TEEFETCH_VERIFIER;

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

    // using bytes memory proof instead of Receipt memory receipt, because interface demands so
    function verify(bytes memory, Attestation memory) external pure {
        revert AttestationVerifierNotImplemented();
    }

    //-------------------------------- Read only methods end -------------------------------//

    function verify(bytes memory data) external {
        (bytes memory _signerPubkey, bytes memory _seal, uint64 _timestampInMilliseconds) = abi.decode(data, (bytes, bytes, uint64));
        TEEFETCH_VERIFIER.enroll(_signerPubkey, _seal, _timestampInMilliseconds);
        console.logBytes(_signerPubkey);
        console.logBytes(_seal);
        console.log("time: ", _timestampInMilliseconds);
        emit AttestationVerified(_signerPubkey, _seal);
    }

}