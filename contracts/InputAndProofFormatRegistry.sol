// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// This is an optional contract that will store the format of inputs and proofs of circuits
/// which can be read by external tools
/// This will initially admin controlled

/// if proofs are in custom structs, this contract won't be helpful
contract InputAndProofFormatRegistry {
    address public immutable admin;

    mapping(bytes32 => string[]) public inputs;
    mapping(bytes32 => string[]) public proofs;

    mapping(bytes32 => uint256) public inputArrayLength;
    mapping(bytes32 => uint256) public proofArrayLength;

    constructor(address _admin) {
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    function setInputFormat(bytes32 marketId, string[] memory inputsFormat) external onlyAdmin {
        inputs[marketId] = inputsFormat;
        inputArrayLength[marketId] = inputsFormat.length;
    }

    function setProofFormat(bytes32 marketId, string[] memory proofFormat) external onlyAdmin {
        proofs[marketId] = proofFormat;
        proofArrayLength[marketId] = proofFormat.length;
    }
}
