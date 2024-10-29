// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MiddlewareFactory is Ownable {
    /// @dev Address of the Middleware implementation contract.
    address public implementation;

    /// @dev Emitted when a new Middleware proxy is deployed.
    /// @param proxyAddress The address of the deployed proxy contract.
    /// @param admin The admin address for the new contract.
    event ContractDeployed(address indexed proxyAddress, address indexed admin);

    /**
     * @dev Constructor sets the implementation address.
     * @param _implementation The address of the Middleware implementation contract.
     */
    constructor(address owner, address _implementation) Ownable(owner) {
        require(_implementation != address(0), "Factory: Implementation address cannot be zero");
        implementation = _implementation;
    }

    /**
     * @dev Deploys and initializes a new Middleware proxy contract.
     * @param _networkId The network identifier.
     * @param _attestationVerifier The address of the attestation verifier contract.
     * @param _admin The address of the admin for the new contract.
     * @return proxyAddress The address of the newly deployed proxy contract.
     */
    function deployMiddleware(
        bytes32 _networkId,
        address _attestationVerifier,
        address _admin
    ) external returns (address proxyAddress) {
        require(_admin != address(0), "Factory: Admin address cannot be zero");
        require(_attestationVerifier != address(0), "Factory: Attestation verifier address cannot be zero");

        // Encode the initialize function call with parameters
        bytes memory initializeData = abi.encodeWithSignature(
            "initialize(bytes32,address,address)",
            _networkId,
            _attestationVerifier,
            _admin
        );

        // Deploy a new proxy contract pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            initializeData
        );

        proxyAddress = address(proxy);

        emit ContractDeployed(proxyAddress, _admin);
    }

    /**
     * @dev Updates the implementation address.
     * @param _newImplementation The address of the new implementation contract.
     */
    function updateImplementation(address _newImplementation) external onlyOwner {
        require(_newImplementation != address(0), "Factory: Implementation address cannot be zero");
        implementation = _newImplementation;
    }
}