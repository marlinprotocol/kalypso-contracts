// SPDX-License-Identifier: MIT

import "./Error.sol";

pragma solidity ^0.8.9;

contract HELPER {
    // function GET_IMAGE_ID_FROM_ATTESTATION(bytes memory data) public pure returns (bytes32) {
    //     (, , , bytes memory PCR0, bytes memory PCR1, bytes memory PCR2, , ) = abi.decode(
    //         data,
    //         (bytes, address, bytes, bytes, bytes, bytes, uint256, uint256)
    //     );

    //     return GET_IMAGED_ID_FROM_PCRS(PCR0, PCR1, PCR2);
    // }

    // function GET_IMAGED_ID_FROM_PCRS(
    //     bytes memory PCR0,
    //     bytes memory PCR1,
    //     bytes memory PCR2
    // ) public pure returns (bytes32) {
    //     bytes32 imageId = keccak256(abi.encodePacked(PCR0, PCR1, PCR2));
    //     return imageId;
    // }

    function GET_PUBKEY_AND_ADDRESS(bytes memory data) public pure returns (bytes memory, address) {
        (, , bytes memory enclaveEciesKey, , , , , ) = abi.decode(
            data,
            (bytes, address, bytes, bytes, bytes, bytes, uint256, uint256)
        );

        return (enclaveEciesKey, PUBKEY_TO_ADDRESS(enclaveEciesKey));
    }

    // TODO: check the validity of the function
    function PUBKEY_TO_ADDRESS(bytes memory publicKey) public pure returns (address) {
        // Ensure the public key is 64 bytes long
        require(publicKey.length == 64, Error.INVALID_ENCLAVE_KEY);

        // Perform the elliptic curve recover operation to get the Ethereum address
        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

    function GET_ETH_SIGNED_HASHED_MESSAGE(bytes32 messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    bytes32 public constant NO_ENCLAVE_ID = 0x99FF0D9125E1FC9531A11262E15AEB2C60509A078C4CC4C64CEFDFB06FF68647;
}
