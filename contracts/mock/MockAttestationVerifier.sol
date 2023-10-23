// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../interfaces/IAttestationVerifier.sol";

contract MockAttestationVerifier is IAttestationVerifier {
    function verify(bytes memory) public pure override returns (bool) {
        return true;
    }

    function safeVerify(bytes memory) public override {}
}
