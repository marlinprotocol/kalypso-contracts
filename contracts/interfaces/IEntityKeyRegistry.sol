// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IAttestationVerifier.sol";

interface IEntityKeyRegistry {
    function attestationVerifier() external returns (IAttestationVerifier);

    function updatePubkey(address key_owner, bytes calldata pub, bytes calldata attestation_data) external;

    function removePubkey() external;
}
