// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract EntityKeyRegistry is
    Initializable,
    ContextUpgradeable,
    ERC165Upgradeable,
    AccessControlUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC1967UpgradeUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    HELPER
{
    IAttestationVerifier public attestationVerifier;

    //-------------------------------- Overrides start --------------------------------//

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _grantRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._grantRole(role, account);
    }

    function _revokeRole(
        bytes32 role,
        address account
    ) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) {
        super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, "Cannot be adminless");
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");

    mapping(address => mapping(uint256 => bytes)) public pub_key;
    mapping(address => bool) public usedUpKey;

    mapping(address => mapping(bytes32 => bytes)) public dedicated_pub_key_per_market;

    modifier isNotUsedUpKey(bytes calldata pubkey) {
        address _address = HELPER.PUBKEY_TO_ADDRESS(pubkey);
        require(!usedUpKey[_address], Error.KEY_ALREADY_EXISTS);
        _;
    }

    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    event UpdateKey(address indexed user, uint256 indexed keyIndex);
    event RemoveKey(address indexed user, uint256 indexed keyIndex);

    function initialize(IAttestationVerifier _attestationVerifier, address _admin) public initializer {
        attestationVerifier = _attestationVerifier;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function updateAttestationVerifier(
        IAttestationVerifier _attestationVerifier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        attestationVerifier = _attestationVerifier;
    }

    function addGeneratorRegistry(address _generatorRegistry) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEY_REGISTER_ROLE, _generatorRegistry);
    }

    function updatePubkey(
        address keyOwner,
        uint256 keyIndex,
        bytes calldata pubkey,
        bytes calldata attestation_data
    ) external onlyRole(KEY_REGISTER_ROLE) isNotUsedUpKey(pubkey) {
        attestationVerifier.verify(attestation_data);
        require(
            block.timestamp <=
                HELPER.GET_TIMESTAMP_IN_SEC_FROM_ATTESTATION(attestation_data) + HELPER.ACCEPTABLE_ATTESTATION_DELAY,
            Error.ATTESTATION_TIMEOUT
        );
        require(pubkey.length == 64, Error.INVALID_ENCLAVE_KEY);

        pub_key[keyOwner][keyIndex] = pubkey;
        address _address = HELPER.PUBKEY_TO_ADDRESS(pubkey);

        usedUpKey[_address] = true;

        emit UpdateKey(keyOwner, keyIndex);
    }

    function removePubkey(address keyOwner, uint256 keyIndex) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[keyOwner][keyIndex];

        emit RemoveKey(keyOwner, keyIndex);
    }
}
