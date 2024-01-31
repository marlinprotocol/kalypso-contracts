// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IAttestationVerifier.sol";

contract MockAttestationVerifier is IAttestationVerifier {
    function verify(
        bytes memory attestation,
        bytes memory enclaveKey,
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2,
        uint256 enclaveCPUs,
        uint256 enclaveMemory,
        uint256 timestamp
    ) public pure override {}

    function verify(bytes memory) public pure override {}

    function isVerified(address) public pure returns (bytes32) {
        return bytes32(0);
    }
}
