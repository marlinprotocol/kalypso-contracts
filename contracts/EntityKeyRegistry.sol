// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";

contract EntityKeyRegistry is AccessControlUpgradeable {
    IAttestationVerifier public immutable attestationVerifier;

    bytes32 public constant GENERATOR_REGISTRY = keccak256("GENERATOR_REGISTRY");

    mapping(address => bytes) public pub_key;

    constructor(IAttestationVerifier _attestationVerifier, address _admin) {
        attestationVerifier = _attestationVerifier;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    event UpdateKey(address indexed user);
    event RemoveKey(address indexed user);

    function addGeneratorRegistry(address _generatorRegistry) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isContract(_generatorRegistry), Error.INVALID_CONTRACT_ADDRESS);
        _grantRole(GENERATOR_REGISTRY, _generatorRegistry);
    }

    function updatePubkey(
        address key_owner,
        bytes calldata pubkey,
        bytes calldata attestation_data
    ) external onlyRole(GENERATOR_REGISTRY) {
        require(attestationVerifier.verify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        require(pubkey.length > 0, Error.INVALID_ENCLAVE_KEY);
        pub_key[key_owner] = pubkey;

        emit UpdateKey(key_owner);
    }

    function removePubkey(address key_owner) external onlyRole(GENERATOR_REGISTRY) {
        delete pub_key[key_owner];

        emit RemoveKey(key_owner);
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
