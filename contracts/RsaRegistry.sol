// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IProofMarketPlace.sol";

contract RsaRegistry {
    IProofMarketPlace public immutable proofMarketPlace;

    mapping(address => bytes) public rsa_pub_key;
    mapping(address => bytes32) public rsa_pub_key_hash;

    constructor(IProofMarketPlace _proofMarketPlace) {
        proofMarketPlace = _proofMarketPlace;
    }

    event UpdateRSA(address indexed user, bytes32 indexed rsa_pub_hash);

    function updatePubkey(bytes calldata rsa_pub) external {
        bytes32 hash = keccak256(rsa_pub);
        address sender = msg.sender;

        rsa_pub_key[sender] = rsa_pub;

        emit UpdateRSA(sender, hash);
    }
}
