// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../EntityKeyRegistry.sol";
import "./Error.sol";
import "./Helper.sol";

contract Dispute {
    using HELPER for bytes;
    using HELPER for bytes32;

    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    constructor(EntityKeyRegistry _er) {
        ENTITY_KEY_REGISTRY = _er;
    }

    function checkDisputeUsingSignature(
        uint256 bidId,
        bytes calldata proverData,
        bytes memory invalidProofSignature,
        bytes32 familyId
    ) internal view returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(bidId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSA.recover(ethSignedMessageHash, invalidProofSignature);
        if (signer == address(0)) {
            revert Error.CannotBeZero();
        }

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

    function checkDispute(
        uint256 bidId,
        bytes calldata proverData,
        bytes calldata invalidProofSignature,
        bytes32 expectedFamilyId
    ) public view returns (bool) {
        return checkDisputeUsingSignature(bidId, proverData, invalidProofSignature, expectedFamilyId);
    }
}
