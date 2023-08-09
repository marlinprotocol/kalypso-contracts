// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IVerifier.sol";

contract MockVerifier is IVerifier {
    function verify(bytes calldata) public pure override returns (bool) {
        return true;
    }
}
