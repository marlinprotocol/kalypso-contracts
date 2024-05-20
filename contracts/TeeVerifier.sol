// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./periphery/AttestationAutherUpgradeable.sol";
import "./periphery/interfaces/IAttestationVerifier.sol";
import "./EntityKeyRegistry.sol";

import "./lib/Error.sol";
import "./lib/Helper.sol";

contract TeeVerifier is 
    Initializable,
    AccessControlUpgradeable,
    AttestationAutherUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IAttestationVerifier _av,
        EntityKeyRegistry _entityRegistry
    ) AttestationAutherUpgradeable(
        _av, 
        HELPER.ACCEPTABLE_ATTESTATION_DELAY
    ) initializer {
        ENTITY_KEY_REGISTRY = _entityRegistry;
    }

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    EntityKeyRegistry public immutable ENTITY_KEY_REGISTRY;

    bytes32 public constant PROOF_MARKETPLACE_ROLE = keccak256("PROOF_MARKETPLACE_ROLE");

    function initialize(address _admin, address _proofMarketplace, EnclaveImage[] memory initWhitelistImages) public initializer {
        __AttestationAuther_init_unchained(initWhitelistImages);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROOF_MARKETPLACE_ROLE, _proofMarketplace);
    }

    function verifyProofForTeeVerifier(
        uint256 askId,
        bytes memory proverData,
        bytes calldata proofSignature,
        bytes32 familyId
    ) external view onlyRole(PROOF_MARKETPLACE_ROLE) returns (bool) {
        bytes32 messageHash = keccak256(abi.encode(askId, proverData));

        bytes32 ethSignedMessageHash = messageHash.GET_ETH_SIGNED_HASHED_MESSAGE();

        address signer = ECDSAUpgradeable.recover(ethSignedMessageHash, proofSignature);
        if (signer == address(0)) {
            revert Error.InvalidEnclaveSignature(signer);
        }

        ENTITY_KEY_REGISTRY.allowOnlyVerifiedFamily(familyId, signer);
        return true;
    }

}