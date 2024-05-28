// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVerifier {
    function verify(bytes calldata encodedPublicInputsAndProofs) external view returns (bool);

    function verifyInputs(bytes calldata inputs) external view returns (bool);

    function sampleInput() external view returns (bytes memory);

    function sampleProof() external view returns (bytes memory);

    function verifyAgainstSampleInputs(bytes memory proof) external view returns (bool);

    function checkSampleInputsAndProof() external view returns (bool);
}
