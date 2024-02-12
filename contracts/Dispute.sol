// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./EntityKeyRegistry.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract Dispute {
    using HELPER for bytes;
    using HELPER for bytes32;

    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    constructor(EntityKeyRegistry _er) {
        ENTITY_KEY_REGISTRY = _er;
    }

    function checkDisputeUsingSignature(
        uint256 askId,
        bytes calldata proverData,
        bytes memory invalidProofSignature,
        bytes32 expectedImageId
    ) internal view returns (bool) {
        bytes32 messageHash;
        bool isPublic = expectedImageId == bytes32(0) || expectedImageId == HELPER.NO_ENCLAVE_ID;

        if (isPublic) {
            messageHash = keccak256(abi.encode(askId, proverData));
        } else {
            messageHash = keccak256(abi.encode(askId));
        }

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, invalidProofSignature);
        require(signer != address(0), Error.CANNOT_BE_ZERO);

        require(ENTITY_KEY_REGISTRY.allowOnlyVerified(signer, expectedImageId), Error.INVALID_ENCLAVE_KEY);
        return true;
    }

    function checkDispute(
        uint256 askId,
        bytes calldata proverData,
        bytes calldata invalidProofSignature,
        bytes32 expectedImageId
    ) public view returns (bool) {
        return checkDisputeUsingSignature(askId, proverData, invalidProofSignature, expectedImageId);
    }
}
