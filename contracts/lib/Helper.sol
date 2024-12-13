// SPDX-License-Identifier: MIT

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Error.sol";

pragma solidity ^0.8.0;

library HELPER {
    function GET_IMAGE_ID_FROM_ATTESTATION(bytes memory data) internal pure returns (bytes32) {
        (, , bytes memory PCR0, bytes memory PCR1, bytes memory PCR2, , , ) = abi.decode(
            data,
            (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256)
        );

        return GET_IMAGE_ID_FROM_PCRS(PCR0, PCR1, PCR2);
    }

    function GET_IMAGE_ID_FROM_PCRS(bytes calldata pcrs) internal pure returns (bytes32) {
        (bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) = abi.decode(pcrs, (bytes, bytes, bytes));
        return GET_IMAGE_ID_FROM_PCRS(PCR0, PCR1, PCR2);
    }

    function GET_IMAGE_ID_FROM_PCRS(bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) internal pure returns (bytes32) {
        bytes32 imageId = keccak256(abi.encodePacked(PCR0, PCR1, PCR2));
        return imageId;
    }

    function GET_PUBKEY_AND_ADDRESS(bytes memory data) internal pure returns (bytes memory, address) {
        (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

        return (enclaveEciesKey, PUBKEY_TO_ADDRESS(enclaveEciesKey));
    }

    function GET_PUBKEY(bytes memory data) internal pure returns (bytes memory) {
        (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

        return (enclaveEciesKey);
    }

    function GET_ADDRESS(bytes memory data) internal pure returns (address) {
        (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

        return (PUBKEY_TO_ADDRESS(enclaveEciesKey));
    }

    function PUBKEY_TO_ADDRESS(bytes memory publicKey) internal pure returns (address) {
        // Ensure the internal key is 64 bytes long
        if (publicKey.length != 64) {
            revert Error.InvalidEnclaveKey();
        }

        // Perform the elliptic curve recover operation to get the Ethereum address
        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

    function GET_ETH_SIGNED_HASHED_MESSAGE(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    function GET_TIMESTAMP_IN_SEC_FROM_ATTESTATION(bytes memory data) internal pure returns (uint256) {
        (, , , , , , , uint256 timestamp) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

        return timestamp / 1000;
    }

    function IS_ENCLAVE(bytes32 imageId) internal pure returns (bool) {
        return !(imageId == bytes32(0) || imageId == NO_ENCLAVE_ID);
    }

    /**
     * @notice Checks if addressToVerify posses access to enclave
     */
    function VERIFY_ENCLAVE_SIGNATURE(
        bytes memory attestationData,
        bytes calldata enclaveSignature,
        address addressToVerify
    ) internal pure {
        bytes32 messageHash = keccak256(abi.encode(attestationData, addressToVerify));
        bytes32 ethSignedMessageHash = GET_ETH_SIGNED_HASHED_MESSAGE(messageHash);

        address signer = ECDSA.recover(ethSignedMessageHash, enclaveSignature);
        if (signer != GET_ADDRESS(attestationData)) {
            revert Error.InvalidEnclaveSignature(signer);
        }
    }

    function MATCHING_ENGINE_FAMILY_ID(bytes32 roleId) internal pure returns (bytes32) {
        return keccak256(abi.encode(roleId));
    }

    function PROVER_FAMILY_ID(uint256 marketId) internal pure returns (bytes32) {
        return keccak256(abi.encode("prov", marketId));
    }

    function IVS_FAMILY_ID(uint256 marketId) internal pure returns (bytes32) {
        return keccak256(abi.encode("ivs", marketId));
    }

    bytes32 internal constant NO_ENCLAVE_ID = 0xcd2e66bf0b91eeedc6c648ae9335a78d7c9a4ab0ef33612a824d91cdc68a4f21;

    uint256 internal constant ACCEPTABLE_ATTESTATION_DELAY = 60000; // 60 seconds, 60,000 milliseconds
}
