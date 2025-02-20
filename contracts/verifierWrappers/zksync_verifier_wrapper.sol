// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {Struct} from "../lib/Struct.sol";
import {Enum} from "../lib/Enum.sol";

interface i_zksync_verifier {
    function verify(uint256[] calldata, uint256[] calldata, uint256[] calldata) external view returns (bool);
}

contract zksync_verifier_wrapper is IVerifier {
    i_zksync_verifier public immutable iverifier;

    bytes public override sampleInput;
    bytes public override sampleProof;

    constructor(i_zksync_verifier _iverifier, bytes memory _sampleInput, bytes memory _sampleProof) {
        iverifier = _iverifier;

        sampleInput = _sampleInput;
        sampleProof = _sampleProof;

        require(checkSampleInputsAndProof(), "Can't be deployed");
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
        uint256[] memory _publicInputs;

        (bytes memory encodedInputs, bytes memory encodedProofs) = abi.decode(encodedData, (bytes, bytes));

        (_publicInputs) = abi.decode(encodedInputs, (uint256[]));

        uint256[] memory _proof;
        uint256[] memory _recursiveAggregationInput;
        (_proof, _recursiveAggregationInput) = abi.decode(encodedProofs, (uint256[], uint256[]));

        return iverifier.verify(_publicInputs, _proof, _recursiveAggregationInput);
    }

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (uint256[] memory) {
        require(verifyInputs(inputs), "Zksync Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (uint256[]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory encodedProof) public view override returns (bool) {
        bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return verify(encodedData);
    }

    function verifyInputs(bytes calldata inputs) public pure override returns (bool) {
        abi.decode(inputs, (uint256[]));
        return true;
    }
}
