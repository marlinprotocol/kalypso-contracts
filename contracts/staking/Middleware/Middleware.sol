// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../../interfaces/staking/symbiotic/IVetoSlasher.sol";
import "../../interfaces/staking/symbiotic/IInstantSlasher.sol";
import "../../interfaces/staking/symbiotic/IVault.sol";
import "../../periphery/interfaces/IAttestationVerifier.sol";

contract Middleware is Initializable,  // initializer
    ContextUpgradeable,  // _msgSender, _msgData
    ERC165Upgradeable,  // supportsInterface
    AccessControlUpgradeable,  // RBAC
    AccessControlEnumerableUpgradeable,  // RBAC enumeration
    UUPSUpgradeable  // public upgrade
{
    // in case we add more contracts in the inheritance chain
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    // initializes the logic contract without any admins
    // safeguard against takeover of the logic contract
    constructor()
        initializer {}

    /**
     * @dev Modifier to restrict access to only admins.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "only admin");
        _;
    }

//-------------------------------- Overrides start --------------------------------//

    /**
     * @dev See {IERC165-supportsInterface}.
     * @param interfaceId The interface identifier.
     * @return True if the contract supports the given interface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Grants `role` to `account`.
     * @param role The role identifier.
     * @param account The account to grant the role to.
     */
    function _grantRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns(bool) {
        return super._grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     * @param role The role identifier.
     * @param account The account to revoke the role from.
     */
    function _revokeRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns(bool) {
        bool status = super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, "M:RR-All admins cant be removed");

        return status;
    }

    /**
     * @dev Authorizes an upgrade to the new implementation.
     */
    function _authorizeUpgrade(address /*account*/) onlyAdmin internal view override {}

//-------------------------------- Overrides end --------------------------------//

//-------------------------------- Initializer start --------------------------------//

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _networkId The network identifier that Middleware represents.
     * @param _attestationVerifier The address of the attestation verifier contract.
     * @param _admin The address of the admin.
     */
    function initialize(bytes32 _networkId, address _attestationVerifier, address _admin) external initializer {
        require(_networkId != bytes32(0), "M:I-Network id cannot be zero");
        require(_attestationVerifier != address(0), "M:I-Attestation verifier cannot be zero address");
        require(_admin != address(0), "M:I-At least one admin necessary");

        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        __UUPSUpgradeable_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _updateNetworkId(_networkId);
        attestationVerifier = _attestationVerifier;
    }

//-------------------------------- Initializer start --------------------------------//

//-------------------------------- Slashing config start --------------------------------//

    /**
     * @dev Enumeration for slasher types.
     */
    enum SlasherType {UNDEFINED, INSTANT_SLASH, VETO_SLASH}

    /**
     * @dev Struct to hold vault information.
     */
    struct VaultInfo {
        uint80 index;
        SlasherType slasherType;
        address collateral;
        address slasher;
    }

    /**
     * @dev Struct to hold slash information.
     */
    struct SlashInfo {
        address operator;
        uint256 amount;
        uint256 captureTimestamp;
        address rewardAddress;
    }

    bytes32 public constant VAULT_CONFIG_SET_ROLE = keccak256("VAULT_CONFIG_SET_ROLE");
    bytes32 public constant NETWORK_UPDATE_ROLE = keccak256("NETWORK_UPDATE_ROLE");
    uint256 private constant SIGNATURE_LENGTH = 65;
    uint256 private constant PUBLIC_KEY_LENGTH = 64;

    bytes32 public networkId;
    address public attestationVerifier;
    mapping(address vault => VaultInfo) public vaultInfo;
    mapping(address vault => mapping(uint256 jobId => SlashInfo)) public slashInfo;
    address[] public vaults;
    mapping(address operator => address delegate) delegates;
    bool public isSlashingEnabled = false;

    uint256[500] private __gap_1;

    /**
     * @dev Emitted when the network ID is updated.
     * @param networkId The new network ID.
     */
    event NetworkIdUpdated(bytes32 indexed networkId);

    /**
     * @dev Emitted when vault information is configured in Middleware.
     * @param vault The address of the vault.
     * @param collateral The address of the collateral used in the vault.
     * @param slasherType The type of slasher configured for the vault.
     */
    event VaultConfigured(address indexed vault, address indexed collateral, SlasherType indexed slasherType);

    /**
     * @dev Emitted when a slash is proposed.
     * @param jobId The job identifier.
     * @param vault The address of the vault.
     * @param operator The address of the operator.
     * @param amount The amount to slash.
     * @param captureTimestamp The timestamp when the stake used for slashing was captured.
     * @param rewardAddress The address to receive the reward for transmitting the slash to Symbiotic contracts.
     */
    event SlashProposed(uint256 indexed jobId, address indexed vault, address indexed operator, uint256 amount, uint256 captureTimestamp, address rewardAddress);

    /**
     * @dev Emitted when a delegate is set for an operator.
     * @param operator The address of the operator.
     * @param delegate The address of the delegate.
     */
    event DelegateSet(address indexed operator, address indexed delegate);

    /**
     * @dev Emitted when slashing is enabled or disabled.
     * @param isEnabled True if slashing is enabled, false otherwise.
     */
    event SlashingEnabled(bool isEnabled);

    /**
     * @dev Enables or disables slashing.
     * @param _isEnabled True to enable slashing, false to disable.
     */
    function setSlashingEnabled(bool _isEnabled) external onlyAdmin() {
        isSlashingEnabled = _isEnabled;
        emit SlashingEnabled(_isEnabled);
    }

    /**
     * @dev Sets a delegate for an operator.
     * @param _delegate The address of the delegate.
     */
    function setDelegate(address _delegate) external {
        require(_delegate != address(0), "M:SD-Delegate cannot be zero address");
        address _operator = _msgSender();
        delegates[_operator] = _delegate;

        emit DelegateSet(_operator, _delegate);
    }

    /**
     * @dev Returns the delegate for an operator.
     * @param _operator The address of the operator.
     * @return The address of the delegate.
     */
    function getDelegate(address _operator) external view returns (address) {
        if(delegates[_operator] == address(0)) {
            return _operator;
        }
        return delegates[_operator];
    }

    /**
     * @dev Configures a vault with the given slasher type. It is possible to override the existing configuration for a vault.
     * @param _vault The address of the vault.
     * @param _type The slasher type.
     */
    function configureVault(address _vault, SlasherType _type) external onlyRole(VAULT_CONFIG_SET_ROLE) {
        require(_vault != address(0), "M:CV-Vault cannot be zero address");
        require(_type != SlasherType(0), "M:CV-Invalid slasher type");
        
        address collateral = IVault(_vault).collateral();
        require(collateral != address(0), "M:CV-Collateral cannot be zero address");
        address slasher = IVault(_vault).slasher();
        require(slasher != address(0), "M:CV-Slasher cannot be zero address");
        if(vaultInfo[_vault].collateral == address(0)) {
            // Add the vault to the list if it is not already present
            vaults.push(_vault);
        }
        vaultInfo[_vault] = VaultInfo(uint80(vaults.length), _type, collateral, slasher);

        emit VaultConfigured(_vault, collateral, _type);
    }

    /**
     * @dev Updates the network ID.
     * @param _networkId The new network ID.
     */
     // TODO: Is this function required?
    function updateNetworkId(bytes32 _networkId) external onlyRole(NETWORK_UPDATE_ROLE) {
        _updateNetworkId(_networkId);
    }

    /**
     * @dev Internal function to update the network ID.
     * @param _networkId The new network ID.
     */
    function _updateNetworkId(bytes32 _networkId) internal {
        require(_networkId != bytes32(0), "M:UN-Network id cannot be zero");
        networkId = _networkId;
        emit NetworkIdUpdated(_networkId);
    }
    
//-------------------------------- Slashing config end --------------------------------//

//-------------------------------- Instant Slashing start --------------------------------//

    /**
     * @dev Performs an instant slash on an operator for a vault.
     * @param _jobId The job identifier.
     * @param _rewardAddress The address for transmitter to receive the reward.
     * @param _vault The address of the vault.
     * @param _operator The address of the operator.
     * @param _amount The amount to slash.
     * @param _captureTimestamp The timestamp when the stake used for slashing was captured.
     * @param _hints Additional hints to optimize search.
     * @param _proof The proof that slashing was invoked on Kalypso contracts with the given parameters.
     */
    function slash(
        uint256 _jobId,
        address _rewardAddress,
        address _vault,
        address _operator,
        uint256 _amount,
        uint48 _captureTimestamp,
        bytes calldata _hints,
        bytes calldata _proof
    ) external { // TODO: Is reentrancy guard required?
        require(isSlashingEnabled, "M:S-Slashing disabled");
        require(vaultInfo[_vault].slasherType == SlasherType.INSTANT_SLASH, "M:S-Invalid slasher type");
        require(_amount != 0, "M:S-Invalid amount");
        require(slashInfo[_vault][_jobId].amount == 0, "M:S-Already slashed");

        _verifyProof(abi.encode(_jobId, _rewardAddress, _vault, _operator, _amount, _captureTimestamp), _proof);

        slashInfo[_vault][_jobId] = SlashInfo(_operator, _amount, _captureTimestamp, _rewardAddress);

        IInstantSlasher(vaultInfo[_vault].slasher).slash(networkId, _operator, _amount, _captureTimestamp, _hints);

        emit SlashProposed(_jobId, _vault, _operator, _amount, _captureTimestamp, _rewardAddress);
    }

//-------------------------------- Instant Slashing end --------------------------------//

//-------------------------------- Veto Slashing start --------------------------------//

    /**
     * @dev Requests a slash on an operator from a vault, subject to veto period.
     * @param _jobId The job identifier.
     * @param _rewardAddress The address to receive the reward.
     * @param _vault The address of the vault.
     * @param _operator The address of the operator.
     * @param _amount The amount to slash.
     * @param _captureTimestamp The timestamp when the stake used for slashing was captured.
     * @param _hints Additional hints to optimize search.
     * @param _proof The proof that slashing was invoked on Kalypso contracts with the given parameters.
     */
    function requestSlash(
        uint256 _jobId,
        address _rewardAddress,
        address _vault,
        address _operator,
        uint256 _amount,
        uint48 _captureTimestamp,
        bytes calldata _hints,
        bytes calldata _proof
    ) external { // TODO: Is reentrancy guard required?
        require(isSlashingEnabled, "M:S-Slashing disabled");
        require(vaultInfo[_vault].slasherType == SlasherType.VETO_SLASH, "M:RS-Invalid slasher type");
        require(_amount != 0, "M:RS-Invalid amount");
        require(slashInfo[_vault][_jobId].amount == 0, "M:RS-Already slashed");

        _verifyProof(abi.encode(_jobId, _rewardAddress, _vault, _operator, _amount, _captureTimestamp), _proof);

        slashInfo[_vault][_jobId] = SlashInfo(_operator, _amount, _captureTimestamp, _rewardAddress);

        IVetoSlasher(vaultInfo[_vault].slasher).requestSlash(networkId, _operator, _amount, _captureTimestamp, _hints);

        emit SlashProposed(_jobId, _vault, _operator, _amount, _captureTimestamp, _rewardAddress);
    }

//-------------------------------- Veto Slashing end --------------------------------//

//-------------------------------- Slashing utils start --------------------------------//

    /**
    * @dev Internal function to verify the proof.
    * The function performs the following steps:
    * - Decodes the proof into the signature and attestation data.
    * - Verifies the signature over the provided data using the enclave key.
    * - Verifies the attestation to ensure the enclave key is valid.
    * - Ensures the enclave key used to sign the data matches the one in the attestation.
    * @param _data The parameters used for slashing.
    * @param _proof  The proof that contains the signature on the parameters used for slashing and 
        attestation data which proves that the key used for signing is securely generated within the enclave.
    */
    function _verifyProof(bytes memory _data, bytes memory _proof) internal view {
        (bytes memory _signature, bytes memory _attestationData) = abi.decode(_proof, (bytes, bytes));
        require(_signature.length == SIGNATURE_LENGTH, "M:VP-Signature length mismatch");
        address _enclaveKey = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(keccak256(_data)), _signature);

        (bytes memory attestationSig, IAttestationVerifier.Attestation memory attestation) = abi.decode(
            _attestationData, 
            (bytes, IAttestationVerifier.Attestation)
        );
        IAttestationVerifier(attestationVerifier).verify(attestationSig, attestation);

        address _verifiedKey = _pubKeyToAddress(attestation.enclavePubKey);
        require(_verifiedKey == _enclaveKey, "M:VP-Enclave key mismatch");
    }

    /**
     * @dev Internal function to convert a public key to an address.
     * @param publicKey The public key bytes.
     * @return The address derived from the public key.
     */
    function _pubKeyToAddress(bytes memory publicKey) internal pure returns (address) {
        require(publicKey.length == PUBLIC_KEY_LENGTH, "M:IPTA-Invalid enclave key");

        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

//-------------------------------- Slashing utils end --------------------------------//

//-------------------------------- utils start --------------------------------//

    /**
     * @dev Returns the list of vault addresses.
     * @return An array of vault addresses.
     */
    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    /**
     * @dev Returns the number of vaults.
     * @return The number of vaults.
     */
    function getNoOfVaults() external view returns (uint256) {
        return vaults.length;
    }

//-------------------------------- utils end --------------------------------//
}