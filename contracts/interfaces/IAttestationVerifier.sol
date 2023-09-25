// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IAttestationVerifier {
    function verify(bytes memory data) external returns (bool);

    function verifyEnclaveKey(bytes memory data) external returns (bool);
}
