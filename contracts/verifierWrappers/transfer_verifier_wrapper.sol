// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";
import "../ProofMarketPlace.sol";

interface i_transfer_verifier {
    function verifyProof(uint256[5] memory input, uint256[8] memory p) external view returns (bool);
}

/// Wrapper contracts are added so that calldata can be modified according to the verifier contract
/// we can modify the verifier contract as well
// but is not recommended as it is a generated contract
contract transfer_verifier_wrapper is IVerifier {
    i_transfer_verifier public immutable iverifier;
    ProofMarketPlace public immutable proofMarketPlace;

    constructor(i_transfer_verifier _iverifier, address _proofMarketPlace) {
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

    function verifyAndDecodeInputs(bytes calldata inputs) public pure returns (uint256[5] memory) {
        require(verifyInputs(inputs), "Transfer Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (uint256[5]));
    }

    function verify(bytes calldata encodedData) public view override returns (bool) {
        uint256[5] memory input;
        uint256[8] memory p;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (input) = abi.decode(encodedInputs, (uint256[5]));
        (p) = abi.decode(encodedProofs, (uint256[8]));

        return iverifier.verifyProof(input, p);
    }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        abi.decode(inputs, (uint256[5]));
        return true;
    }

    function encodeInputs(uint256[5] memory inputs) public pure returns (bytes memory) {
        return abi.encode(inputs);
    }

    function encodeProof(uint256[8] memory proof) public pure returns (bytes memory) {
        return abi.encode(proof);
    }

    function encodeInputAndProofForVerification(
        uint256[5] memory inputs,
        uint256[8] memory proof
    ) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }
}
