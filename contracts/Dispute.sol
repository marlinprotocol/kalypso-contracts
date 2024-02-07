// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract Dispute {
    using HELPER for bytes;
    using HELPER for bytes32;

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

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

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
        bytes32 imageId = attestationData.GET_IMAGE_ID_FROM_ATTESTATION();
        require(imageId == expectedImageId, Error.INCORRECT_IMAGE_ID);

        require(
            block.timestamp <=
                attestationData.GET_TIMESTAMP_IN_SEC_FROM_ATTESTATION() + HELPER.ACCEPTABLE_ATTESTATION_DELAY,
            Error.ATTESTATION_TIMEOUT
        );

        (, address signer) = attestationData.GET_PUBKEY_AND_ADDRESS();

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
