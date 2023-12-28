// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IAttestationVerifier.sol";
import "./lib/Error.sol";

contract EntityKeyRegistry is AccessControlUpgradeable {
    IAttestationVerifier public immutable attestationVerifier;

    bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");

    mapping(address => bytes) public pub_key;

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
    ) external onlyRole(KEY_REGISTER_ROLE) {
        require(attestationVerifier.verify(attestation_data), Error.ENCLAVE_KEY_NOT_VERIFIED);
        require(pubkey.length != 0, Error.INVALID_ENCLAVE_KEY);
        pub_key[key_owner] = pubkey;

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

    function getPubkeyAndAddress(bytes memory data) public pure returns (bytes memory, address) {
        (, , bytes memory enclaveEciesKey, , , , , ) = abi.decode(
            data,
            (bytes, address, bytes, bytes, bytes, bytes, uint256, uint256)
        );

        return (enclaveEciesKey, publicKeyToAddress(enclaveEciesKey));
    }

    // TODO: check the validity of the function
    function publicKeyToAddress(bytes memory publicKey) public pure returns (address) {
        // Ensure the public key is 64 bytes long
        require(publicKey.length == 64, Error.INVALID_ENCLAVE_KEY);

        // Perform the elliptic curve recover operation to get the Ethereum address
        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }
}
