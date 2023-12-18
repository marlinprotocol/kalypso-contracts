// SPDX-License-Identifier: MIT

import "../ProofMarketPlace.sol";

pragma solidity ^0.8.9;

abstract contract IVerifier {
    ProofMarketPlace public proofMarketPlace;

    function setProofMarketPlaceContract(ProofMarketPlace _proofMarketplace) external {
        require(address(proofMarketPlace) == address(0), "Already Set");
        proofMarketPlace = _proofMarketplace;
    }

    function verify(bytes calldata encodedPublicInputsAndProofs) external view virtual returns (bool);

    function verifyInputs(bytes calldata inputs) external view virtual returns (bool);

    function sampleInput() external view virtual returns (bytes memory);

    function sampleProof() external view virtual returns (bytes memory);

    function verifyAgainstSampleInputs(bytes memory proof) external view virtual returns (bool);

    function checkSampleInputsAndProof() external view virtual returns (bool);
}
