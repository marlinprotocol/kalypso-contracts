// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {SetPmp} from "../interfaces/SetPmp.sol";
import {IProofMarketplace} from "../interfaces/IProofMarketplace.sol";
import {Struct} from "../lib/Struct.sol";
import {Enum} from "../lib/Enum.sol";
interface i_plonk_vk {
    function verify(bytes calldata _proof, bytes32[] calldata _publicInputs) external view returns (bool);
}

/// Wrapper contracts are added so that calldata can be modified according to the verifier contract
/// we can modify the verifier contract as well
// but is not recommended as it is a generated contract
contract plonk_verifier_wrapper is SetPmp, IVerifier {
    i_plonk_vk public immutable iverifier;

    bytes public override sampleInput;
    bytes public override sampleProof;

    constructor(i_plonk_vk _iverifier, bytes memory _sampleInput, bytes memory _sampleProof) {
        iverifier = _iverifier;
        sampleInput = _sampleInput;
        sampleProof = _sampleProof;
    }

    function createRequest(
        Struct.Bid calldata bid,
        Enum.SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public {
        Struct.Bid memory newBid = Struct.Bid(
            bid.marketId,
            bid.reward,
            bid.expiry,
            bid.timeTakenForProofGeneration,
            bid.deadline,
            bid.refundAddress,
            encodeInputs(verifyAndDecodeInputs(bid.proverData))
        );

        proofMarketplace.createBid(newBid, secretType, secret_inputs, acl);
    }

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (bytes32[] memory) {
        require(verifyInputs(inputs), "Plonk Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (bytes32[]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return verify(encodedData);
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
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

    function encodeInputAndProofForVerification(bytes32[] memory inputs, bytes memory proof) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }
}
