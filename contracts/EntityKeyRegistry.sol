// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";
import "./lib/Helper.sol";

contract EntityKeyRegistry is AccessControl, HELPER {
    IAttestationVerifier public immutable attestationVerifier;

    bytes32 public constant KEY_REGISTER_ROLE = bytes32(uint256(keccak256("KEY_REGISTER_ROLE")) - 1);

    mapping(address => bytes) public pub_key;
    mapping(address => bool) public usedUpKey;

    modifier isNotUsedUpKey(bytes calldata pubkey) {
        address _address = publicKeyToAddress(pubkey);
        require(!usedUpKey[_address], Error.KEY_ALREADY_EXISTS);
        _;
    }

    constructor(IAttestationVerifier _attestationVerifier, address _admin) {
        attestationVerifier = _attestationVerifier;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    event UpdateKey(address indexed user);
    event RemoveKey(address indexed user);

    function addGeneratorRegistry(address _generatorRegistry) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isContract(_generatorRegistry), Error.INVALID_CONTRACT_ADDRESS);
        _grantRole(KEY_REGISTER_ROLE, _generatorRegistry);
    }

    function updatePubkey(
        address key_owner,
        bytes calldata pubkey,
        bytes calldata attestation_data
    ) external onlyRole(KEY_REGISTER_ROLE) isNotUsedUpKey(pubkey) {
        require(attestationVerifier.verify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        require(pubkey.length == 64, Error.INVALID_ENCLAVE_KEY);

        pub_key[key_owner] = pubkey;
        address _address = publicKeyToAddress(pubkey);

        usedUpKey[_address] = true;

        emit UpdateKey(key_owner);
    }

    function removePubkey(address key_owner) external onlyRole(KEY_REGISTER_ROLE) {
        delete pub_key[key_owner];

        emit RemoveKey(key_owner);
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
