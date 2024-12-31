// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

/// This is an optional contract that will store the format of inputs and proofs of circuits
/// which can be read by external tools
/// This will initially admin controlled

/// if proofs are in custom structs, this contract won't be helpful
contract InputAndProofFormatRegistry {
    address public immutable admin;

    mapping(uint256 => string[]) public inputs;
    mapping(uint256 => string[]) public proofs;

    mapping(uint256 => uint256) public inputArrayLength;
    mapping(uint256 => uint256) public proofArrayLength;

    constructor(address _admin) {
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    function setInputFormat(uint256 marketId, string[] memory inputsFormat) external onlyAdmin {
        inputs[marketId] = inputsFormat;
        inputArrayLength[marketId] = inputsFormat.length;
    }

    function setProofFormat(uint256 marketId, string[] memory proofFormat) external onlyAdmin {
        proofs[marketId] = proofFormat;
        proofArrayLength[marketId] = proofFormat.length;
    }
}
