// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/SetPmp.sol";
import "../interfaces/IVerifier.sol";

interface i_transfer_verifier {
    function verifyProof(uint256[5] memory input, uint256[8] memory p) external view returns (bool);
}

/// Wrapper contracts are added so that calldata can be modified according to the verifier contract
/// we can modify the verifier contract as well
// but is not recommended as it is a generated contract
contract transfer_verifier_wrapper is SetPmp, IVerifier {
    i_transfer_verifier public immutable iverifier;

    bytes public override sampleInput;
    bytes public override sampleProof;

    constructor(i_transfer_verifier _iverifier, bytes memory _sampleInput, bytes memory _sampleProof) {
        iverifier = _iverifier;

        sampleInput = _sampleInput;
        sampleProof = _sampleProof;

        require(checkSampleInputsAndProof(), "Can't be deployed");
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

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (uint256[5] memory) {
        require(verifyInputs(inputs), "Transfer Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (uint256[5]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return verify(encodedData);
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
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

    function encodeInputAndProofForVerification(uint256[5] memory inputs, uint256[8] memory proof) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }
}
