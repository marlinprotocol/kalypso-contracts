// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";

interface i_transfer_verifier {
    function verifyProof(uint256[5] memory input, uint256[8] memory p) external view returns (bool);
}

/// Wrapper contracts are added so that calldata can be modified according to the verifier contract
/// we can modify the verifier contract as well
// but is not recommended as it is a generated contract
contract transfer_verifier_wrapper is IVerifier {
    i_transfer_verifier public immutable iverifier;

    constructor(i_transfer_verifier _iverifier) {
        iverifier = _iverifier;
    }

    function verify(bytes calldata encodedData) public view returns (bool) {
        uint256[5] memory input;
        uint256[8] memory p;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (input) = abi.decode(encodedInputs, (uint256[5]));
        (p) = abi.decode(encodedProofs, (uint256[8]));

        return iverifier.verifyProof(input, p);
    }
}
