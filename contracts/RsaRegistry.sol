// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IRsaRegistry.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";

contract RsaRegistry is IRsaRegistry {
    IAttestationVerifier public immutable attestationVerifier;

    mapping(address => bytes) public rsa_pub_key;
    mapping(address => bytes32) public rsa_pub_key_hash;

    constructor(IAttestationVerifier _attestationVerifier) {
        attestationVerifier = _attestationVerifier;
    }

    event UpdateRSA(address indexed user, bytes32 indexed rsa_pub_hash);

    function updatePubkey(bytes calldata rsa_pub, bytes calldata attestation_data) external {
        bytes32 hash = keccak256(rsa_pub);
        address sender = msg.sender;

        // TODO: Use the actual data
        require(attestationVerifier.verify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        rsa_pub_key[sender] = rsa_pub;

        emit UpdateRSA(sender, hash);
    }
}
