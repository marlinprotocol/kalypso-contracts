// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../periphery/AttestationAuther.sol";
import "../lib/Helper.sol";
import "../interfaces/IVerifier.sol";

contract tee_verifier_wrapper_factory {
    function create_tee_verifier_wrapper(IAttestationVerifier _av, bytes[] calldata _proverPcrs) public returns (tee_verifier_wrapper) {
        return new tee_verifier_wrapper(_av, _proverPcrs);
    }
}

contract tee_verifier_wrapper is AttestationAuther, IVerifier {
    bytes public override sampleInput;
    bytes public override sampleProof;

    using HELPER for bytes32;
    using HELPER for bytes;

    bytes32 constant FAMILY_ID = keccak256("FAMILY_ID");

    constructor(IAttestationVerifier _av, bytes[] memory _proverPcrs) AttestationAuther(_av, HELPER.ACCEPTABLE_ATTESTATION_DELAY) {
        for (uint256 index = 0; index < _proverPcrs.length; index++) {
            (bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) = abi.decode(_proverPcrs[index], (bytes, bytes, bytes));

            bytes32 imageId = PCR0.GET_IMAGE_ID_FROM_PCRS(PCR1, PCR2);
            if (!imageId.IS_ENCLAVE()) {
                revert Error.MustBeAnEnclave(imageId);
            }

            (bytes32 inferredImageId, ) = _whitelistEnclaveImage(EnclaveImage(PCR0, PCR1, PCR2));

            if (inferredImageId != imageId) {
                revert Error.InferredImageIdIsDifferent();
            }
            _addEnclaveImageToFamily(imageId, FAMILY_ID);
        }
    }

    function verifyKey(bytes calldata attestation_data) external {
        _verifyKeyInternal(attestation_data);
    }

    function verifyAndDecodeInputs(bytes calldata inputs) internal pure returns (string[] memory) {
        require(verifyInputs(inputs), "TEE Verifier Wrapper: Invalid input format");
        return abi.decode(inputs, (string[]));
    }

    function checkSampleInputsAndProof() public view override returns (bool) {
        return verifyAgainstSampleInputs(sampleProof);
    }

    function verifyAgainstSampleInputs(bytes memory) public pure override returns (bool) {
        // bytes memory encodedData = abi.encode(sampleInput, encodedProof);
        return true;
    }

    function verify(bytes memory encodedData) public view override returns (bool) {
        (bytes memory encodedInputs, bytes memory encodedProof, bytes memory proofSignature) = abi.decode(
            encodedData,
            (bytes, bytes, bytes)
        );

        return verifyProofForTeeVerifier(encodedInputs, encodedProof, proofSignature);
    }

    function verifyProofForTeeVerifier(
        bytes memory proverData,
        bytes memory proofData,
        bytes memory proofSignature
    ) public view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(proverData, proofData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, proofSignature);
        if (signer == address(0)) {
            revert Error.InvalidEnclaveSignature(signer);
        }

        _allowOnlyVerifiedFamily(signer, FAMILY_ID);
        return true;
    }

    function verifyInputs(bytes calldata) public pure override returns (bool) {
        // abi.decode(inputs, (string[]));
        return true;
    }

    function encodeInputs(string[] memory inputs) public pure returns (bytes memory) {
        return abi.encode(inputs);
    }

    function encodeProof(string memory proof) public pure returns (bytes memory) {
        return abi.encode(proof);
    }

    function encodeInputAndProofForVerification(string[] memory inputs, string memory proof) public pure returns (bytes memory) {
        return abi.encode(encodeInputs(inputs), encodeProof(proof));
    }

    function _verifyKeyInternal(bytes calldata data) internal {
        (
            bytes memory attestation,
            bytes memory enclaveKey,
            bytes memory PCR0,
            bytes memory PCR1,
            bytes memory PCR2,
            uint256 timestamp
        ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256));

        // compute image id in proper way
        _verifyEnclaveKey(attestation, IAttestationVerifier.Attestation(enclaveKey, PCR0, PCR1, PCR2, timestamp));
    }
}
