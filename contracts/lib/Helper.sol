// SPDX-License-Identifier: MIT

import "./Error.sol";

pragma solidity ^0.8.9;

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

    function GET_IMAGE_ID_FROM_PCRS(
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2
    ) internal pure returns (bytes32) {
        bytes32 imageId = keccak256(abi.encodePacked(PCR0, PCR1, PCR2));
        return imageId;
    }

    function GET_PUBKEY_AND_ADDRESS(bytes memory data) internal pure returns (bytes memory, address) {
        (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(
            data,
            (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256)
        );

        return (enclaveEciesKey, PUBKEY_TO_ADDRESS(enclaveEciesKey));
    }

    function PUBKEY_TO_ADDRESS(bytes memory publicKey) internal pure returns (address) {
        // Ensure the internal key is 64 bytes long
        require(publicKey.length == 64, Error.INVALID_ENCLAVE_KEY);

        // Perform the elliptic curve recover operation to get the Ethereum address
        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

    function GET_ETH_SIGNED_HASHED_MESSAGE(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    function GET_TIMESTAMP_IN_SEC_FROM_ATTESTATION(bytes memory data) internal pure returns (uint256) {
        (, , , , , , , uint256 timestamp) = abi.decode(
            data,
            (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256)
        );

        return timestamp / 1000;
    }

    bytes32 internal constant NO_ENCLAVE_ID = 0xcd2e66bf0b91eeedc6c648ae9335a78d7c9a4ab0ef33612a824d91cdc68a4f21;

    uint256 internal constant ACCEPTABLE_ATTESTATION_DELAY = 60000; // 60 seconds, 60,000 milliseconds
}
