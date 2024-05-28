// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IVerifier.sol";
import "../EntityKeyRegistry.sol";

contract tee_verifier_wrapper is IVerifier {
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;
    bytes public override sampleInput;
    bytes public override sampleProof;

    using HELPER for bytes32;

    constructor(EntityKeyRegistry _entityRegistry) {
        ENTITY_KEY_REGISTRY = _entityRegistry;
        require(checkSampleInputsAndProof(), "Can't be deployed");
    }

    function createRequest(
        ProofMarketplace.Ask calldata ask,
        ProofMarketplace.SecretType secretType,
        bytes calldata secret_inputs,
        bytes calldata acl
    ) public {
        ProofMarketplace.Ask memory newAsk = ProofMarketplace.Ask(
            ask.marketId,
            ask.reward,
            ask.expiry,
            ask.timeTakenForProofGeneration,
            ask.deadline,
            ask.refundAddress,
            encodeInputs(verifyAndDecodeInputs(ask.proverData))
        );

        proofMarketplace.createAsk(newAsk, secretType, abi.encode(secret_inputs), abi.encode(acl));
    }

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (string[] memory) {
        require(verifyInputs(inputs), "TEE Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (string[]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        // bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return true;
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
        uint256 askId;
        bytes memory proofSignature;
        bytes32 familyId;

        (bytes memory encodedAskId, bytes memory encodedInputs, bytes memory encodedProofSignature, bytes memory encodedFamilyId) = abi
            .decode(encodedData, (bytes, bytes, bytes, bytes));

        (askId) = abi.decode(encodedAskId, (uint256));
        (proofSignature) = abi.decode(encodedProofSignature, (bytes));
        (familyId) = abi.decode(encodedFamilyId, (bytes32));

        return verifyProofForTeeVerifier(askId, encodedInputs, proofSignature, familyId);
    }

    function verifyProofForTeeVerifier(
        uint256 askId,
        bytes memory proverData,
        bytes memory proofSignature,
        bytes32 familyId
    ) public view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(askId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, proofSignature);
        if (signer == address(0)) {
            revert Error.InvalidEnclaveSignature(signer);
        }

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        // abi.decode(inputs, (string[]));
        return true;
    }

    function encodeInputs(string[] memory inputs) public pure returns (bytes memory) {
        return abi.encode(inputs);
    }

    function encodeProof(string memory proof) public pure returns (bytes memory) {
        return abi.encode(proof);
    }

    function encodeInputAndProofForVerification(string[] memory inputs, string memory proof) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }
}
