// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract Dispute is HELPER {
    function checkDisputeUsingSignature(
        uint256 askId,
        bytes memory invalidProofSignature,
        address expectedSigner
    ) public pure returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(askId));

        bytes32 ethSignedMessageHash = HELPER.GET_ETH_SIGNED_HASHED_MESSAGE(messageHash);

        address signer = ECDSA.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer == expectedSigner, Error.INVALID_ENCLAVE_KEY);
        return true;
    }

    function checkDisputeUsingAttesation(
        uint256 askId,
        bytes memory attestationData,
        bytes32 expectedImageId,
        bytes memory invalidProofSignature
    ) public pure returns (bool) {
        bytes32 imageId = HELPER.GET_IMAGE_ID_FROM_ATTESTATION(attestationData);
        require(imageId == expectedImageId, Error.INCORRECT_IMAGE_ID);

        (, address signer) = HELPER.GET_PUBKEY_AND_ADDRESS(attestationData);

        return checkDisputeUsingSignature(askId, invalidProofSignature, signer);
    }

    function checkDisputeUsingAttestationAndOrSignature(
        uint256 askId,
        bytes calldata completeData,
        bytes32 expectedImageId,
        address defaultIvsSigner
    ) public pure returns (bool) {
        (bytes memory attestationData, bytes memory invalidProofSignature, bool useOnlySignature) = abi.decode(
            completeData,
            (bytes, bytes, bool)
        );

        if (useOnlySignature) {
            return checkDisputeUsingSignature(askId, invalidProofSignature, defaultIvsSigner);
        }

        return checkDisputeUsingAttesation(askId, attestationData, expectedImageId, invalidProofSignature);
    }
}
