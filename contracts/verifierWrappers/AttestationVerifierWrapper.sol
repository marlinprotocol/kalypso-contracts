// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../periphery/interfaces/IAttestationVerifier.sol";
import "../interfaces/SetPmp.sol";
import "../interfaces/IVerifier.sol";

interface i_risc0_attestation_verifier {
    function verify(bytes memory data) external view;
}

contract AttestationProofVerifierWrapper is SetPmp, IVerifier {
    i_risc0_attestation_verifier public immutable iverifier;

    bytes public override sampleInput;
    bytes public override sampleProof;

    constructor(i_risc0_attestation_verifier _iverifier, bytes memory _sampleInput, bytes memory _sampleProof) {
        iverifier = _iverifier;

        sampleInput = _sampleInput;
        sampleProof = _sampleProof;

        require(checkSampleInputsAndProof(), "Can't be deployed");
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return verify(encodedData);
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
        iverifier.verify(encodedData);
        return true;
    }

    function verifyInputs(bytes calldata) public pure override returns (bool) {
        // TODO: figure out way to verifyInputs, If not possible else simply return true.
        // abi.decode(inputs, (IAttestationVerifier.Attestation));
        return true;
    }
}
