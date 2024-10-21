// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../interfaces/staking/symbiotic/IVetoSlasher.sol";
import "../interfaces/staking/symbiotic/IInstantSlasher.sol";
import "../interfaces/staking/symbiotic/IVault.sol";
import "../periphery/interfaces/IAttestationVerifier.sol";

contract AttestationAutherSample is Initializable,  // initializer
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

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "only admin");
        _;
    }

//-------------------------------- Overrides start --------------------------------//

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _grantRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns(bool) {
        return super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override(AccessControlUpgradeable, AccessControlEnumerableUpgradeable) returns(bool) {
        bool status = super._revokeRole(role, account);

        // protect against accidentally removing all admins
        require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0, "AAS:RR-All admins cant be removed");

        return status;
    }

    function _authorizeUpgrade(address /*account*/) onlyAdmin internal view override {}

//-------------------------------- Overrides end --------------------------------//

//-------------------------------- Initializer start --------------------------------//

    function initialize(bytes32 _networkId, address _attestationVerifier, address _admin) external initializer {
        require(_admin != address(0), "AAS:I-At least one admin necessary");

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

    enum SlasherType {INSTANT_SLASH, VETO_SLASH}
    struct VaultInfo {
        uint80 index;
        SlasherType slasherType;
        address collateral;
        address slasher;
    }
    struct SlashInfo {
        address operator;
        uint256 amount;
        uint256 captureTimestamp;
        address rewardAddress;
    }

    bytes32 public constant SLASH_TYPE_SET_ROLE = keccak256("SLASH_TYPE_SET_ROLE");
    bytes32 public constant NETWORK_UPDATE_ROLE = keccak256("NETWORK_UPDATE_ROLE");

    bytes32 public networkId;
    address public attestationVerifier;
    mapping(address vault => VaultInfo) public vaultInfo;
    mapping(address vault => mapping(uint256 jobId => SlashInfo)) public slashInfo;
    address[] public vaults;

    event NetworkIdUpdated(bytes32 indexed networkId);
    event VaultInfoUpdated(address indexed vault, address indexed collateral, SlasherType indexed slasherType);
    event SlashProposed(uint256 indexed jobId, address indexed vault, address indexed operator, uint256 amount, uint256 captureTimestamp, address rewardAddress);

    function configureVault(address _vault, SlasherType _type) external onlyRole(SLASH_TYPE_SET_ROLE) {
        require(_vault != address(0), "W:CV-Vault cannot be zero address");
        
        address collateral = IVault(_vault).collateral();
        require(collateral != address(0), "W:CV-Collateral cannot be zero address");
        // NOTE: slasher can be set later in vault, hence it can be zero address
        address slasher = IVault(_vault).slasher();
        require((slasher == address(0)) == (_type == SlasherType(0)), "W:CV-Slasher and type mismatch");
        vaultInfo[_vault] = VaultInfo(uint80(vaults.length), _type, collateral, slasher);
        vaults.push(_vault);

        emit VaultInfoUpdated(_vault, collateral, _type);
    }

    function updateVault(address _vault, SlasherType _type) external onlyRole(SLASH_TYPE_SET_ROLE) {
        require(_vault != address(0), "W:UV-Vault cannot be zero address");
        require(vaultInfo[_vault].slasherType != SlasherType(0), "W:UV-Slasher not set");
        require(vaultInfo[_vault].slasher == address(0), "W:UV-Slasher already set");

        address slasher = IVault(_vault).slasher();
        require(slasher != address(0), "W:UV-Collateral cannot be zero address");
        vaultInfo[_vault].slasher = slasher;
        vaultInfo[_vault].slasherType = _type;

        emit VaultInfoUpdated(_vault, vaultInfo[_vault].collateral, _type);
    }

    function updateNetworkId(bytes32 _networkId) external onlyRole(NETWORK_UPDATE_ROLE) {
        _updateNetworkId(_networkId);
    }

    function _updateNetworkId(bytes32 _networkId) internal {
        networkId = _networkId;
        emit NetworkIdUpdated(_networkId);
    }
    
//-------------------------------- Slashing config end --------------------------------//

//-------------------------------- Instant Slashing start --------------------------------//

    function slash(
        uint256 _jobId,
        address _rewardAddress,
        address _vault,
        address _operator,
        uint256 _amount,
        uint48 _captureTimestamp,
        bytes calldata _hints,
        bytes calldata _proof
    ) external {
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

    function requestSlash(
        uint256 _jobId,
        address _rewardAddress,
        address _vault,
        address _operator,
        uint256 _amount,
        uint48 _captureTimestamp,
        bytes calldata _hints,
        bytes calldata _proof
    ) external {
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

    function _verifyProof(bytes memory _data, bytes memory _proof) internal view {
        (bytes memory _signature, bytes memory _attestationData) = abi.decode(_proof, (bytes, bytes));
        require(_signature.length == 65, "M:VP-Signature length mismatch");

        address _enclaveKey = ECDSA.recover(keccak256(_data), _signature);

        (bytes memory attestationSig, IAttestationVerifier.Attestation memory attestation) = abi.decode(
            _attestationData, 
            (bytes, IAttestationVerifier.Attestation)
        );
        IAttestationVerifier(attestationVerifier).verify(attestationSig, attestation);

        address _verifiedKey = _pubKeyToAddress(attestation.enclavePubKey);
        require(_verifiedKey == _enclaveKey, "M:VP-Enclave key mismatch");
    }

    function _pubKeyToAddress(bytes memory publicKey) internal pure returns (address) {
        require(publicKey.length == 64, "M:IPTA-Invalid enclave key");

        bytes32 hash = keccak256(publicKey);
        return address(uint160(uint256(hash)));
    }

//-------------------------------- Slashing utils end --------------------------------//

//-------------------------------- utils start --------------------------------//

    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    function getNoOfVaults() external view returns (uint256) {
        return vaults.length;
    }

//-------------------------------- utils end --------------------------------//
}