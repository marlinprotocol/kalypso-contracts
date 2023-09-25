// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IProofMarketPlace.sol";
import "./interfaces/IAttestationVerifier.sol";

contract RsaRegistry {
    IProofMarketPlace public immutable proofMarketPlace;
    IAttestationVerifier public immutable attestationVerifier;

    mapping(address => bytes) public rsa_pub_key;
    mapping(address => bytes32) public rsa_pub_key_hash;

    constructor(IProofMarketPlace _proofMarketPlace, IAttestationVerifier _attestationVerifier) {
        proofMarketPlace = _proofMarketPlace;
        attestationVerifier = _attestationVerifier;
    }

    event UpdateRSA(address indexed user, bytes32 indexed rsa_pub_hash);

    function updatePubkey(bytes calldata rsa_pub, bytes calldata attestation_data) external {
        bytes32 hash = keccak256(rsa_pub);
        address sender = msg.sender;

        require(attestationVerifier.verifyEnclaveKey(attestation_data), "Enclave Key is not verified");
        rsa_pub_key[sender] = rsa_pub;

        emit UpdateRSA(sender, hash);
    }
}
