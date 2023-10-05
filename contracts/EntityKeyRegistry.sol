// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IEntityKeyRegistry.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";

contract EntityKeyRegistry is IEntityKeyRegistry {
    IAttestationVerifier public immutable attestationVerifier;

    mapping(address => bytes) public pub_key;

    constructor(IAttestationVerifier _attestationVerifier) {
        attestationVerifier = _attestationVerifier;
    }

    event UpdateKey(address indexed user);

    function updatePubkey(bytes calldata pubkey, bytes calldata attestation_data) external {
        address sender = msg.sender;

        require(attestationVerifier.safeVerify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        pub_key[sender] = pubkey;

        emit UpdateKey(sender);
    }
}
