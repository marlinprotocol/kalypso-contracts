// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract Dispute is HELPER {
    IAttestationVerifier public immutable ATTESTATION_VERIFIER;

    constructor(IAttestationVerifier _attestationVerifier) {
        ATTESTATION_VERIFIER = _attestationVerifier;
    }

    function checkDisputeUsingSignature(
        uint256 askId,
        bytes calldata proverData,
        bytes memory invalidProofSignature,
        address expectedSigner,
        bool isPublic
    ) internal pure returns (bool) {
        bytes32 messageHash;
        if (isPublic) {
            messageHash = keccak256(abi.encode(askId, proverData));
        } else {
            messageHash = keccak256(abi.encode(askId));
        }

        bytes32 ethSignedMessageHash = HELPER.GET_ETH_SIGNED_HASHED_MESSAGE(messageHash);

        address signer = ECDSA.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer == expectedSigner, Error.INVALID_ENCLAVE_KEY);
        return true;
    }

    function checkDisputeUsingAttesation(
        uint256 askId,
        bytes calldata proverData,
        bytes memory attestationData,
        bytes32 expectedImageId,
        bytes memory invalidProofSignature
    ) internal view returns (bool) {
        bytes32 imageId = HELPER.GET_IMAGE_ID_FROM_ATTESTATION(attestationData);
        require(imageId == expectedImageId, Error.INCORRECT_IMAGE_ID);

        require(block.timestamp <= HELPER.GET_TIMESTAMP_FROM_ATTESTATION(attestationData), Error.ATTESTATION_TIMEOUT);

        (, address signer) = HELPER.GET_PUBKEY_AND_ADDRESS(attestationData);

        return
            checkDisputeUsingSignature(
                askId,
                proverData,
                invalidProofSignature,
                signer,
                expectedImageId == bytes32(0) || expectedImageId == HELPER.NO_ENCLAVE_ID
            );
    }

    function checkDisputeUsingAttestationAndOrSignature(
        uint256 askId,
        bytes calldata proverData,
        bytes calldata completeData,
        bytes32 expectedImageId,
        address defaultIvsSigner
    ) public view returns (bool) {
        (bytes memory attestationData, bytes memory invalidProofSignature, bool useOnlySignature) = abi.decode(
            completeData,
            (bytes, bytes, bool)
        );

        ATTESTATION_VERIFIER.verify(attestationData);

        if (useOnlySignature) {
            return
                checkDisputeUsingSignature(
                    askId,
                    proverData,
                    invalidProofSignature,
                    defaultIvsSigner,
                    expectedImageId == bytes32(0) || expectedImageId == HELPER.NO_ENCLAVE_ID
                );
        }

        return checkDisputeUsingAttesation(askId, proverData, attestationData, expectedImageId, invalidProofSignature);
    }
}
