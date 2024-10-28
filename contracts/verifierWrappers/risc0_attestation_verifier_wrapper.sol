// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../periphery/interfaces/IAttestationVerifier.sol";
import "../interfaces/SetPmp.sol";
import "../interfaces/IVerifier.sol";

interface i_risc0_attestation_verifier {
    function verify(bytes memory proof, IAttestationVerifier.Attestation memory attestation) external view;

    function verify(bytes memory data) external view;
}

contract risc0_attestation_verifier_wrapper is SetPmp, IVerifier {
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
        bytes memory encodedData = abi.encode(encodedProof, sampleInput);
        return verify(encodedData);
    }

    // function verify(bytes memory encodedData) public view override returns (bool) {
    //     IAttestationVerifier.Attestation memory attestationInput;
    //     bytes memory proof;

    //     (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

    //     (attestationInput) = abi.decode(encodedInputs, (IAttestationVerifier.Attestation));
    //     (proof) = abi.decode(encodedProofs, (bytes));

    //     // revert if wrong proof, so fine
    //     iverifier.verify(proof, attestationInput);

    //     return true;
    // }

    function verify(bytes memory encodedData) public view override returns (bool) {
        // IAttestationVerifier.Attestation memory attestationInput;

        // (bytes memory encodedInputs, bytes memory proof) = abi.decode(encodedData, (bytes, bytes));

        // (attestationInput) = abi.decode(encodedInputs, (IAttestationVerifier.Attestation));

        // revert if wrong proof, so fine
        iverifier.verify(encodedData);

        return true;
    }

    // function verify(bytes memory encodedData) public view override returns (bool) {

    //     (IAttestationVerifier.Attestation memory attestationInput, bytes memory proof) = abi.decode(encodedData, (IAttestationVerifier.Attestation, bytes));

    //     // revert if wrong proof, so fine
    //     iverifier.verify(proof, attestationInput);

    //     return true;
    // }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        abi.decode(inputs, (IAttestationVerifier.Attestation));
        return true;
    }
}
