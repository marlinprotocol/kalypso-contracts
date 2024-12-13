// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import "../periphery/interfaces/IAttestationVerifier.sol";

contract MockAttestationVerifier is IAttestationVerifier {
    function verify(
        bytes memory attestation,
        bytes memory enclaveKey,
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2,
        uint256 timestamp
    ) public pure {}

    function verify(bytes memory) public pure override {}

    function verify(bytes memory signature, IAttestationVerifier.Attestation memory attestation) external pure {}
}
