// SPDX-License-Identifier: MIT

import "./Error.sol";

pragma solidity ^0.8.9;

contract HELPER {
    function getPubkeyAndAddress(bytes memory data) public pure returns (bytes memory, address) {
        (, , bytes memory enclaveEciesKey, , , , , ) = abi.decode(
            data,
            (bytes, address, bytes, bytes, bytes, bytes, uint256, uint256)
        );

        return (enclaveEciesKey, publicKeyToAddress(enclaveEciesKey));
    }

    // TODO: check the validity of the function
    function publicKeyToAddress(bytes memory publicKey) public pure returns (address) {
        // Ensure the public key is 64 bytes long
        require(publicKey.length == 64, Error.INVALID_ENCLAVE_KEY);

        // Perform the elliptic curve recover operation to get the Ethereum address
        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

    function getEthSignedMessageHash(bytes32 messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }
}
