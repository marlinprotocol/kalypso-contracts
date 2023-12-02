// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";
import "../ProofMarketPlace.sol";

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
    ProofMarketPlace public immutable proofMarketPlace;

    constructor(i_xor2_verifier _iverifier, address _proofMarketPlace) {
        iverifier = _iverifier;
        proofMarketPlace = ProofMarketPlace(_proofMarketPlace);
    }

    function createRequest(
        ProofMarketPlace.Ask calldata ask,
        bool hasPrivateInputs,
        ProofMarketPlace.SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public {
        ProofMarketPlace.Ask memory newAsk = ProofMarketPlace.Ask(
            ask.marketId,
            ask.reward,
            ask.expiry,
            ask.timeTakenForProofGeneration,
            ask.deadline,
            ask.refundAddress,
            encodeInputs(verifyAndDecodeInputs(ask.proverData))
        );

        if (hasPrivateInputs) {
            proofMarketPlace.createAsk(
                newAsk,
                hasPrivateInputs,
                secretType,
                abi.encode(secret_inputs),
                abi.encode(acl)
            );
        } else {
            proofMarketPlace.createAsk(newAsk, hasPrivateInputs, secretType, "0x", "0x");
        }
    }

    function verifyAndDecodeInputs(bytes calldata inputs) public pure returns (uint[1] memory) {
        require(verifyInputs(inputs), "Circom Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (uint[1]));
    }

    function verify(bytes calldata encodedData) public view override returns (bool) {
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
