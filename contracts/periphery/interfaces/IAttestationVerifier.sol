// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

interface IAttestationVerifier {
    struct Attestation {
        bytes enclavePubKey;
        bytes PCR0;
        bytes PCR1;
        bytes PCR2;
        uint256 timestampInMilliseconds;
    }

    function verify(bytes memory signature, Attestation memory attestation) external view;

    function verify(bytes memory data) external view;
}
