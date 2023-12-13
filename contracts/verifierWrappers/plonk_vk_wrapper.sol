// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";
import "../ProofMarketPlace.sol";

interface i_plonk_vk {
    function verify(bytes calldata _proof, bytes32[] calldata _publicInputs) external view returns (bool);
}

/// Wrapper contracts are added so that calldata can be modified according to the verifier contract
/// we can modify the verifier contract as well
// but is not recommended as it is a generated contract
contract plonk_verifier_wrapper is IVerifier {
    i_plonk_vk public immutable iverifier;
    ProofMarketPlace public immutable proofMarketPlace;

    constructor(i_plonk_vk _iverifier, address _proofMarketPlace) {
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

    function verifyAndDecodeInputs(bytes calldata inputs) public pure returns (bytes32[] memory) {
        require(verifyInputs(inputs), "Plonk Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (bytes32[]));
    }

    function verify(bytes calldata encodedData) public view override returns (bool) {
        bytes32[] memory _publicInputs;
        bytes memory _proof;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (_publicInputs) = abi.decode(encodedInputs, (bytes32[]));
        (_proof) = abi.decode(encodedProofs, (bytes));

        return iverifier.verify(_proof, _publicInputs);
    }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        abi.decode(inputs, (bytes32[]));
        return true;
    }

    function encodeInputs(bytes32[] memory inputs) public pure returns (bytes memory) {
        return abi.encode(inputs);
    }

    function encodeProof(bytes memory proof) public pure returns (bytes memory) {
        return abi.encode(proof);
    }

    function encodeInputAndProofForVerification(
        bytes32[] memory inputs,
        bytes memory proof
    ) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }
}
