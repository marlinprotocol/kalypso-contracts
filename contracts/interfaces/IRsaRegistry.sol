// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IAttestationVerifier.sol";

interface IRsaRegistry {
    function attestationVerifier() external returns (IAttestationVerifier);

    function updatePubkey(bytes calldata rsa_pub, bytes calldata attestation_data) external;
}
