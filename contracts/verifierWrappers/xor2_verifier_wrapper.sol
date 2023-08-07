// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";

interface i_xor2_verifier {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[1] memory input
    ) external view returns (bool);
}

contract xor2_verifier_wrapper is IVerifier {
    i_xor2_verifier public immutable iverifier;

    constructor(i_xor2_verifier _iverifier) {
        iverifier = _iverifier;
    }

    function verify(bytes calldata encodedData) public view returns (bool) {
        uint[2] memory a;
        uint[2][2] memory b;
        uint[2] memory c;
        uint[1] memory input;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (input) = abi.decode(encodedInputs, (uint[1]));
        (a, b, c) = abi.decode(encodedProofs, (uint[2], uint[2][2], uint[2]));

        return iverifier.verifyProof(a, b, c, input);
    }

    function encodeInputs(uint[1] memory inputs) public pure returns (bytes memory) {
        return abi.encode(inputs);
    }

    function encodeProof(uint[2] memory a, uint[2][2] memory b, uint[2] memory c) public pure returns (bytes memory) {
        return abi.encode(a, b, c);
    }

    function encodeInputAndProofForVerification(
        uint[1] memory inputs,
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c
    ) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(a, b, c));
    }
}
