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
import "./periphery/AttestationAutherUpgradeable.sol";

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
    AttestationAutherUpgradeable
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        IAttestationVerifier _av
    ) AttestationAutherUpgradeable(_av, HELPER.ACCEPTABLE_ATTESTATION_DELAY) initializer {}

    using HELPER for bytes;
    using HELPER for bytes32;

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
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, Error.CANNOT_BE_ADMIN_LESS);
    }

    function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");

    mapping(address => mapping(uint256 => bytes)) public pub_key;

    modifier isNotUsedUpKey(bytes calldata pubkey) {
        address _address = pubkey.PUBKEY_TO_ADDRESS();
        require(_getVerifiedKey(_address) == bytes32(0), Error.KEY_ALREADY_EXISTS);
        _;
    }

    event UpdateKey(address indexed user, uint256 indexed keyIndex);
    event RemoveKey(address indexed user, uint256 indexed keyIndex);

    function initialize(address _admin, EnclaveImage[] memory initWhitelistImages) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        __AttestationAuther_init_unchained(initWhitelistImages);
    }

    function addGeneratorRegistry(address _generatorRegistry) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(KEY_REGISTER_ROLE, _generatorRegistry);
    }

    function updatePubkey(
        address keyOwner,
        uint256 keyIndex,
        bytes calldata pubkey,
        bytes calldata attestation_data,
        bool whitelistImage
    ) external onlyRole(KEY_REGISTER_ROLE) isNotUsedUpKey(pubkey) {
        require(pubkey.length == 64, Error.INVALID_ENCLAVE_KEY);

        pub_key[keyOwner][keyIndex] = pubkey;

        _verifyKeyInternal(attestation_data, whitelistImage);

        emit UpdateKey(keyOwner, keyIndex);
    }

    function whitelistImageIfNot(bytes calldata attestation_data) external onlyRole(KEY_REGISTER_ROLE) {
        (, , bytes memory PCR0, bytes memory PCR1, bytes memory PCR2, , , ) = abi.decode(
            attestation_data,
            (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256)
        );

        _whitelistImageIfNot(PCR0, PCR1, PCR2);
    }

    function whitelistImageIfNot(
        bytes memory PCR0,
        bytes memory PCR1,
        bytes memory PCR2
    ) external onlyRole(KEY_REGISTER_ROLE) {
        _whitelistImageIfNot(PCR0, PCR1, PCR2);
    }

    function _verifyKeyInternal(bytes calldata data, bool whitelistImage) internal {
        (
            bytes memory attestation,
            bytes memory enclaveKey,
            bytes memory PCR0,
            bytes memory PCR1,
            bytes memory PCR2,
            uint256 enclaveCPUs,
            uint256 enclaveMemory,
            uint256 timestamp
        ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

        if (whitelistImage) {
            _whitelistImageIfNot(PCR0, PCR1, PCR2);
        }
        // compute image id in proper way
        _verifyKey(
            attestation,
            enclaveKey,
            PCR0.GET_IMAGED_ID_FROM_PCRS(PCR1, PCR2),
            enclaveCPUs,
            enclaveMemory,
            timestamp
        );
    }

    function _whitelistImageIfNot(bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) internal {
        bytes32 imageId = PCR0.GET_IMAGED_ID_FROM_PCRS(PCR1, PCR2);
        if (_getWhitelistedImage(imageId).PCR0.length == 0) {
            _whitelistEnclaveImage(EnclaveImage(PCR0, PCR1, PCR2));
        }
    }

    function removePubkey(address keyOwner, uint256 keyIndex) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[keyOwner][keyIndex];

        emit RemoveKey(keyOwner, keyIndex);
    }

    // for further increase
    uint256[50] private __gap1_0;
}
