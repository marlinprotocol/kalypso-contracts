// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IVerifier {
    function verify(bytes calldata encodedPublicAndPrivateInputs) external view returns (bool);
}
