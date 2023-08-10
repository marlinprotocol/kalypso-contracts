// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

abstract contract IVerifier {
    function verify(bytes calldata encodedPublicInputsAndProofs) external view virtual returns (bool);

    function verifyInputs(bytes calldata inputs) external view virtual returns (bool);
}
