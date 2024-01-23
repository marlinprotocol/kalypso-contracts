// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IAttestationVerifier.sol";

contract MockAttestationVerifier is IAttestationVerifier {
    function verify(
        bytes memory attestation,
        address sourceEnclaveKey,
        address enclaveKey,
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2,
        uint256 enclaveCPUs,
        uint256 enclaveMemory
    ) public pure override returns (bool) {
        return true;
    }

    function safeVerify(
        bytes memory attestation,
        address sourceEnclaveKey,
        address enclaveKey,
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2,
        uint256 enclaveCPUs,
        uint256 enclaveMemory
    ) public pure override {}

    function verify(bytes memory) public pure override returns (bool) {
        return true;
    }

    function safeVerify(bytes memory data) public pure override {}

    function isVerified(address) public pure returns (bytes32) {
        return bytes32(0);
    }
}
