// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";

contract EntityKeyRegistry is AccessControlUpgradeable {
    IAttestationVerifier public immutable attestationVerifier;

    bytes32 public constant KEY_REGISTER_ROLE = bytes32(uint256(keccak256("KEY_REGISTER_ROLE")) - 1);

    mapping(address => bytes) public pub_key;

    constructor(IAttestationVerifier _attestationVerifier, address key_register) {
        attestationVerifier = _attestationVerifier;
        _grantRole(KEY_REGISTER_ROLE, key_register);
    }

    event UpdateKey(address indexed user);
    event RemoveKey(address indexed user);

    function updatePubkey(address key_owner, bytes calldata pubkey, bytes calldata attestation_data) external onlyRole(KEY_REGISTER_ROLE) {
        require(attestationVerifier.verify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        pub_key[key_owner] = pubkey;

        emit UpdateKey(key_owner);
    }

    function removePubkey(address key_owner) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[key_owner];

        emit RemoveKey(key_owner);
    }
}
