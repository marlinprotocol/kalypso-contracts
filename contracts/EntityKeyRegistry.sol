// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract EntityKeyRegistry is AccessControl, HELPER {
    IAttestationVerifier public immutable attestationVerifier;

    bytes32 public constant KEY_REGISTER_ROLE = bytes32(uint256(keccak256("KEY_REGISTER_ROLE")) - 1);

    mapping(address => mapping(uint256 => bytes)) public pub_key;
    mapping(address => bool) public usedUpKey;

    mapping(address => mapping(bytes32 => bytes)) public dedicated_pub_key_per_market;

    modifier isNotUsedUpKey(bytes calldata pubkey) {
        address _address = HELPER.PUBKEY_TO_ADDRESS(pubkey);
        require(!usedUpKey[_address], Error.KEY_ALREADY_EXISTS);
        _;
    }

    constructor(IAttestationVerifier _attestationVerifier, address _admin) {
        attestationVerifier = _attestationVerifier;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    event UpdateKey(address indexed user, uint256 indexed keyIndex);
    event RemoveKey(address indexed user, uint256 indexed keyIndex);

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
        require(block.timestamp <= HELPER.GET_TIMESTAMP_FROM_ATTESTATION(attestation_data), Error.ATTESTATION_TIMEOUT);
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
