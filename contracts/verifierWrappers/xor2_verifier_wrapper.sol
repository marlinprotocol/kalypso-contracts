// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/SetPmp.sol";
import "../interfaces/IVerifier.sol";

interface i_xor2_verifier {
    function verifyProof(uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[1] memory input) external view returns (bool);
}

contract xor2_verifier_wrapper is SetPmp, IVerifier {
    i_xor2_verifier public immutable iverifier;

    bytes public override sampleInput;
    bytes public override sampleProof;

    constructor(i_xor2_verifier _iverifier, bytes memory _sampleInput, bytes memory _sampleProof) {
        iverifier = _iverifier;
        sampleInput = _sampleInput;
        sampleProof = _sampleProof;
    }

    function createRequest(
        ProofMarketplace.Bid calldata bid,
        ProofMarketplace.SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public {
        ProofMarketplace.Bid memory newBid = ProofMarketplace.Bid(
            bid.marketId,
            bid.reward,
            bid.expiry,
            bid.timeTakenForProofGeneration,
            bid.deadline,
            bid.refundAddress,
            encodeInputs(verifyAndDecodeInputs(bid.proverData))
        );

        proofMarketplace.createBid(newBid, secretType, abi.encode(secret_inputs), abi.encode(acl));
    }

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (uint[1] memory) {
        require(verifyInputs(inputs), "Circom Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (uint[1]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return verify(encodedData);
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
        uint[2] memory a;
        uint[2][2] memory b;
        uint[2] memory c;
        uint[1] memory input;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (input) = abi.decode(encodedInputs, (uint[1]));
        (a, b, c) = abi.decode(encodedProofs, (uint[2], uint[2][2], uint[2]));

        return iverifier.verifyProof(a, b, c, input);
    }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        abi.decode(inputs, (bytes32[]));
        return true;
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
