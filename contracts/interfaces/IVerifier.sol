// SPDX-License-Identifier: MIT

import "../ProofMarketPlace.sol";

pragma solidity ^0.8.9;

abstract contract IVerifier {
    ProofMarketplace public proofMarketplace;

    function setProofMarketplaceContract(ProofMarketplace _proofMarketplace) external {
        require(address(proofMarketplace) == address(0), "Already Set");
        proofMarketplace = _proofMarketplace;
    }

    function verify(bytes calldata encodedPublicInputsAndProofs) external view virtual returns (bool);

    function verifyInputs(bytes calldata inputs) external view virtual returns (bool);

    function sampleInput() external view virtual returns (bytes memory);

    function sampleProof() external view virtual returns (bytes memory);

    function verifyAgainstSampleInputs(bytes memory proof) external view virtual returns (bool);

    function checkSampleInputsAndProof() external view virtual returns (bool);
}
