// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IVerifier.sol";

contract MockVerifier is IVerifier {
    bytes public override sampleInput;
    bytes public override sampleProof;

    function verify(bytes calldata) public pure override returns (bool) {
        return true;
    }

    function verifyInputs(bytes calldata) public pure override returns (bool) {
        return true;
    }

    function checkSampleInputsAndProof() public pure override returns (bool) {
        return true;
    }

    function verifyAgainstSampleInputs(bytes memory) public pure override returns (bool) {
        return true;
    }
}
