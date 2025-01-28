// // SPDX-License-Identifier: MIT
// pragma solidity =0.8.26 ^0.8.0 ^0.8.20 ^0.8.21 ^0.8.9;

// // contracts/lib/Error.sol

// library Error {
//     // Administrative and Miscellaneous Errors
//     error OnlyAdminCanCall();
//     error CannotBeAdminLess();
//     error CannotBeZero();
//     error CannotBeSlashed();
//     error InsufficientStakeToLock();
//     error EnclaveKeyNotVerified();
//     error ExceedsAcceptableRange();
//     error InvalidContractAddress();
//     error CannotUseMatchingEngineRole();
//     error InvalidEnclaveSignature(address invalidSignerAddress);
//     error IncorrectImageId();
//     error AttestationTimeout();
//     error InvalidECIESACL();
//     error BlacklistedImage(bytes32 imageId);
//     error AlreadyABlacklistedImage(bytes32 imageId);
//     error MustBeAnEnclave(bytes32 imageId);
//     error FailedWhitelistingImages(bytes32 imageId);
//     error FailedAddingToFamily(bytes32 imageId, bytes32 familyId);
//     error InferredImageIdIsDifferent();
//     error ImageAlreadyInFamily(bytes32 imageId, bytes32 familyId);

//     // Prover-related Errors
//     error ProverAlreadyExists();
//     error InvalidProver();
//     error InvalidProverCommission();
//     error CannotLeaveWithActiveMarket();
//     error AssignOnlyToIdleProvers();
//     error InsufficientProverComputeAvailable();
//     error OnlyWorkingProvers();
//     error InvalidEnclaveKey();
//     error OnlyValidProversCanRequestExit();
//     error InvalidProverStatePerMarket();
//     error UnstakeRequestNotInPlace();
//     error ReduceComputeRequestNotInPlace();
//     error MaxParallelRequestsPerMarketExceeded();
//     error KeyAlreadyExists(address _address);
//     error ReductionRequestNotValid();
//     error PublicMarketsDontNeedKey();
//     error CannotModifyImagesForPublicMarkets();

//     // Market-related Errors
//     error InvalidMarket();
//     error AlreadyJoinedMarket();
//     error CannotBeMoreThanDeclaredCompute();
//     error CannotLeaveMarketWithActiveRequest();
//     error MarketAlreadyExists();
//     error InactiveMarket();
//     error OnlyMarketCreator();
//     error CannotRemoveDefaultImageFromMarket(uint256 marketId, bytes32 imageId);
//     error NoRewardToClaim();

//     // Task and Request Errors
//     error CannotAssignExpiredTasks();
//     error InvalidInputs();
//     error ArityMismatch();
//     error OnlyMatchingEngineCanAssign();
//     error RequestAlreadyInPlace();
//     error CannotSlashUsingValidInputs(uint256 bidId);

//     // Proof and State Errors
//     error ShouldBeInCreateState();
//     error ProofPriceMismatch(uint256 bidId);
//     error ProofTimeMismatch(uint256 bidId);
//     error OnlyExpiredBidsCanBeCancelled(uint256 bidId);
//     error OnlyAssignedBidsCanBeProved(uint256 bidId);
//     error InvalidProof(uint256 bidId);
//     error DeadlineNotCrossed(uint256 bidId);
//     error ShouldBeInAssignedState(uint256 bidId);
//     error OnlyProverCanDiscardRequest(uint256 bidId);

//     // ProverManager
//     error ZeroProverDataLength();
//     error ZeroComputeToIncrease();
//     error ZeroComputeToReduce();
//     error ZeroRewardAddress();
//     error ZeroDeclaredCompute();
//     error ZeroNewRewardAddress();
//     error ProverNotRegistered();
    
//     // ProofMarketplace
//     error InvalidProverRewardShare();
//     error NotSlashableBidId(uint256 bidId);

//     // Staking
//     error InsufficientStakeAmount();
//     error NoStakeTokenAvailableToLock();
//     error ZeroTokenAddress();
//     error ZeroToAddress();

//     // StakingManager
//     error InvalidPool();
//     error PoolAlreadyExists();
//     error InvalidLength();
//     error InvalidShares();
    
//     // Symbiotic Staking
//     error InvalidSlashResultBlockRange();
//     error EndBlockBeforeStartBlock();
//     error NotRegisteredBlockNumber();
//     error NotRegisteredTransmitter();
//     error SubmissionAlreadyCompleted();
//     error InvalidIndex();
//     error ZeroNumOfTxs();
//     error InvalidCaptureTimestamp();
//     error CooldownPeriodNotPassed();
//     error NotIdxToSubmit();
//     error ImageNotFound();
//     error InvalidSignatureLength();
//     error EnclaveKeyMismatch();
//     error InvalidImage();
//     error InvalidPublicKeyLength();
//     error InvalidLastBlockNumber();
//     error ImageAlreadyExists();
//     error InvalidPCR0Length();
//     error InvalidPCR1Length();
//     error InvalidPCR2Length();
//     error ZeroStakeTokenSelectionWeightSum();
//     error NoStakeTokensAvailable();
//     error TokenAlreadyExists();
//     error TokenDoesNotExist();
//     error InvalidComissionRate();

//     // Native Staking
//     error OnlyProverCanStake();
//     error InsufficientStake();
//     error InvalidIndexLength();
//     error OnlyProverCanWithdrawStake();
//     error WithdrawalTimeNotReached();
//     error InvalidWithdrawalAmount();
//     error TokenNotSupported();
//     error InvalidWithdrawalDuration();

//     // SymbioticStakingReward
//     error OnlyStakingManager();
//     error ZeroProofMarketplaceAddress();
//     error ZeroSymbioticStakingAddress();

//     // Contract Address
//     error InvalidStakingManager();
//     error InvalidFeeToken();
//     error InvalidSymbioticStaking();
// }

// // contracts/periphery/interfaces/IAttestationVerifier.sol

// interface IAttestationVerifier {
//     struct Attestation {
//         bytes enclavePubKey;
//         bytes PCR0;
//         bytes PCR1;
//         bytes PCR2;
//         uint256 timestampInMilliseconds;
//     }

//     function verify(bytes memory signature, Attestation memory attestation) external view;

//     function verify(bytes memory data) external view;
// }

// // node_modules/@openzeppelin/contracts/access/IAccessControl.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (access/IAccessControl.sol)

// /**
//  * @dev External interface of AccessControl declared to support ERC-165 detection.
//  */
// interface IAccessControl {
//     /**
//      * @dev The `account` is missing a role.
//      */
//     error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

//     /**
//      * @dev The caller of a function is not the expected one.
//      *
//      * NOTE: Don't confuse with {AccessControlUnauthorizedAccount}.
//      */
//     error AccessControlBadConfirmation();

//     /**
//      * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
//      *
//      * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
//      * {RoleAdminChanged} not being emitted signaling this.
//      */
//     event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

//     /**
//      * @dev Emitted when `account` is granted `role`.
//      *
//      * `sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
//      * Expected in cases where the role was granted using the internal {AccessControl-_grantRole}.
//      */
//     event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

//     /**
//      * @dev Emitted when `account` is revoked `role`.
//      *
//      * `sender` is the account that originated the contract call:
//      *   - if using `revokeRole`, it is the admin role bearer
//      *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
//      */
//     event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

//     /**
//      * @dev Returns `true` if `account` has been granted `role`.
//      */
//     function hasRole(bytes32 role, address account) external view returns (bool);

//     /**
//      * @dev Returns the admin role that controls `role`. See {grantRole} and
//      * {revokeRole}.
//      *
//      * To change a role's admin, use {AccessControl-_setRoleAdmin}.
//      */
//     function getRoleAdmin(bytes32 role) external view returns (bytes32);

//     /**
//      * @dev Grants `role` to `account`.
//      *
//      * If `account` had not been already granted `role`, emits a {RoleGranted}
//      * event.
//      *
//      * Requirements:
//      *
//      * - the caller must have ``role``'s admin role.
//      */
//     function grantRole(bytes32 role, address account) external;

//     /**
//      * @dev Revokes `role` from `account`.
//      *
//      * If `account` had been granted `role`, emits a {RoleRevoked} event.
//      *
//      * Requirements:
//      *
//      * - the caller must have ``role``'s admin role.
//      */
//     function revokeRole(bytes32 role, address account) external;

//     /**
//      * @dev Revokes `role` from the calling account.
//      *
//      * Roles are often managed via {grantRole} and {revokeRole}: this function's
//      * purpose is to provide a mechanism for accounts to lose their privileges
//      * if they are compromised (such as when a trusted device is misplaced).
//      *
//      * If the calling account had been granted `role`, emits a {RoleRevoked}
//      * event.
//      *
//      * Requirements:
//      *
//      * - the caller must be `callerConfirmation`.
//      */
//     function renounceRole(bytes32 role, address callerConfirmation) external;
// }

// // node_modules/@openzeppelin/contracts/interfaces/IERC1967.sol

// // OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC1967.sol)

// /**
//  * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
//  */
// interface IERC1967 {
//     /**
//      * @dev Emitted when the implementation is upgraded.
//      */
//     event Upgraded(address indexed implementation);

//     /**
//      * @dev Emitted when the admin account has changed.
//      */
//     event AdminChanged(address previousAdmin, address newAdmin);

//     /**
//      * @dev Emitted when the beacon is changed.
//      */
//     event BeaconUpgraded(address indexed beacon);
// }

// // node_modules/@openzeppelin/contracts/interfaces/draft-IERC1822.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (interfaces/draft-IERC1822.sol)

// /**
//  * @dev ERC-1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
//  * proxy whose upgrades are fully controlled by the current implementation.
//  */
// interface IERC1822Proxiable {
//     /**
//      * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
//      * address.
//      *
//      * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
//      * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
//      * function revert if invoked through a proxy.
//      */
//     function proxiableUUID() external view returns (bytes32);
// }

// // node_modules/@openzeppelin/contracts/proxy/beacon/IBeacon.sol

// // OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/IBeacon.sol)

// /**
//  * @dev This is the interface that {BeaconProxy} expects of its beacon.
//  */
// interface IBeacon {
//     /**
//      * @dev Must return an address that can be used as a delegate call target.
//      *
//      * {UpgradeableBeacon} will check that this address is a contract.
//      */
//     function implementation() external view returns (address);
// }

// // node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

// /**
//  * @dev Interface of the ERC-20 standard as defined in the ERC.
//  */
// interface IERC20 {
//     /**
//      * @dev Emitted when `value` tokens are moved from one account (`from`) to
//      * another (`to`).
//      *
//      * Note that `value` may be zero.
//      */
//     event Transfer(address indexed from, address indexed to, uint256 value);

//     /**
//      * @dev Emitted when the allowance of a `spender` for an `owner` is set by
//      * a call to {approve}. `value` is the new allowance.
//      */
//     event Approval(address indexed owner, address indexed spender, uint256 value);

//     /**
//      * @dev Returns the value of tokens in existence.
//      */
//     function totalSupply() external view returns (uint256);

//     /**
//      * @dev Returns the value of tokens owned by `account`.
//      */
//     function balanceOf(address account) external view returns (uint256);

//     /**
//      * @dev Moves a `value` amount of tokens from the caller's account to `to`.
//      *
//      * Returns a boolean value indicating whether the operation succeeded.
//      *
//      * Emits a {Transfer} event.
//      */
//     function transfer(address to, uint256 value) external returns (bool);

//     /**
//      * @dev Returns the remaining number of tokens that `spender` will be
//      * allowed to spend on behalf of `owner` through {transferFrom}. This is
//      * zero by default.
//      *
//      * This value changes when {approve} or {transferFrom} are called.
//      */
//     function allowance(address owner, address spender) external view returns (uint256);

//     /**
//      * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
//      * caller's tokens.
//      *
//      * Returns a boolean value indicating whether the operation succeeded.
//      *
//      * IMPORTANT: Beware that changing an allowance with this method brings the risk
//      * that someone may use both the old and the new allowance by unfortunate
//      * transaction ordering. One possible solution to mitigate this race
//      * condition is to first reduce the spender's allowance to 0 and set the
//      * desired value afterwards:
//      * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
//      *
//      * Emits an {Approval} event.
//      */
//     function approve(address spender, uint256 value) external returns (bool);

//     /**
//      * @dev Moves a `value` amount of tokens from `from` to `to` using the
//      * allowance mechanism. `value` is then deducted from the caller's
//      * allowance.
//      *
//      * Returns a boolean value indicating whether the operation succeeded.
//      *
//      * Emits a {Transfer} event.
//      */
//     function transferFrom(address from, address to, uint256 value) external returns (bool);
// }

// // node_modules/@openzeppelin/contracts/utils/Errors.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

// /**
//  * @dev Collection of common custom errors used in multiple contracts
//  *
//  * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
//  * It is recommended to avoid relying on the error API for critical functionality.
//  *
//  * _Available since v5.1._
//  */
// library Errors {
//     /**
//      * @dev The ETH balance of the account is not enough to perform the operation.
//      */
//     error InsufficientBalance(uint256 balance, uint256 needed);

//     /**
//      * @dev A call to an address target failed. The target may have reverted.
//      */
//     error FailedCall();

//     /**
//      * @dev The deployment failed.
//      */
//     error FailedDeployment();

//     /**
//      * @dev A necessary precompile is missing.
//      */
//     error MissingPrecompile(address);
// }

// // node_modules/@openzeppelin/contracts/utils/StorageSlot.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// // This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

// /**
//  * @dev Library for reading and writing primitive types to specific storage slots.
//  *
//  * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
//  * This library helps with reading and writing to such slots without the need for inline assembly.
//  *
//  * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
//  *
//  * Example usage to set ERC-1967 implementation slot:
//  * ```solidity
//  * contract ERC1967 {
//  *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
//  *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
//  *
//  *     function _getImplementation() internal view returns (address) {
//  *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
//  *     }
//  *
//  *     function _setImplementation(address newImplementation) internal {
//  *         require(newImplementation.code.length > 0);
//  *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
//  *     }
//  * }
//  * ```
//  *
//  * TIP: Consider using this library along with {SlotDerivation}.
//  */
// library StorageSlot {
//     struct AddressSlot {
//         address value;
//     }

//     struct BooleanSlot {
//         bool value;
//     }

//     struct Bytes32Slot {
//         bytes32 value;
//     }

//     struct Uint256Slot {
//         uint256 value;
//     }

//     struct Int256Slot {
//         int256 value;
//     }

//     struct StringSlot {
//         string value;
//     }

//     struct BytesSlot {
//         bytes value;
//     }

//     /**
//      * @dev Returns an `AddressSlot` with member `value` located at `slot`.
//      */
//     function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
//      */
//     function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
//      */
//     function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
//      */
//     function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns a `Int256Slot` with member `value` located at `slot`.
//      */
//     function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns a `StringSlot` with member `value` located at `slot`.
//      */
//     function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
//      */
//     function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := store.slot
//         }
//     }

//     /**
//      * @dev Returns a `BytesSlot` with member `value` located at `slot`.
//      */
//     function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := slot
//         }
//     }

//     /**
//      * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
//      */
//     function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
//         assembly ("memory-safe") {
//             r.slot := store.slot
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts/utils/cryptography/ECDSA.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/ECDSA.sol)

// /**
//  * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
//  *
//  * These functions can be used to verify that a message was signed by the holder
//  * of the private keys of a given address.
//  */
// library ECDSA {
//     enum RecoverError {
//         NoError,
//         InvalidSignature,
//         InvalidSignatureLength,
//         InvalidSignatureS
//     }

//     /**
//      * @dev The signature derives the `address(0)`.
//      */
//     error ECDSAInvalidSignature();

//     /**
//      * @dev The signature has an invalid length.
//      */
//     error ECDSAInvalidSignatureLength(uint256 length);

//     /**
//      * @dev The signature has an S value that is in the upper half order.
//      */
//     error ECDSAInvalidSignatureS(bytes32 s);

//     /**
//      * @dev Returns the address that signed a hashed message (`hash`) with `signature` or an error. This will not
//      * return address(0) without also returning an error description. Errors are documented using an enum (error type)
//      * and a bytes32 providing additional information about the error.
//      *
//      * If no error is returned, then the address can be used for verification purposes.
//      *
//      * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
//      * this function rejects them by requiring the `s` value to be in the lower
//      * half order, and the `v` value to be either 27 or 28.
//      *
//      * IMPORTANT: `hash` _must_ be the result of a hash operation for the
//      * verification to be secure: it is possible to craft signatures that
//      * recover to arbitrary addresses for non-hashed data. A safe way to ensure
//      * this is by receiving a hash of the original message (which may otherwise
//      * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
//      *
//      * Documentation for signature generation:
//      * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
//      * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
//      */
//     function tryRecover(
//         bytes32 hash,
//         bytes memory signature
//     ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
//         if (signature.length == 65) {
//             bytes32 r;
//             bytes32 s;
//             uint8 v;
//             // ecrecover takes the signature parameters, and the only way to get them
//             // currently is to use assembly.
//             assembly ("memory-safe") {
//                 r := mload(add(signature, 0x20))
//                 s := mload(add(signature, 0x40))
//                 v := byte(0, mload(add(signature, 0x60)))
//             }
//             return tryRecover(hash, v, r, s);
//         } else {
//             return (address(0), RecoverError.InvalidSignatureLength, bytes32(signature.length));
//         }
//     }

//     /**
//      * @dev Returns the address that signed a hashed message (`hash`) with
//      * `signature`. This address can then be used for verification purposes.
//      *
//      * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
//      * this function rejects them by requiring the `s` value to be in the lower
//      * half order, and the `v` value to be either 27 or 28.
//      *
//      * IMPORTANT: `hash` _must_ be the result of a hash operation for the
//      * verification to be secure: it is possible to craft signatures that
//      * recover to arbitrary addresses for non-hashed data. A safe way to ensure
//      * this is by receiving a hash of the original message (which may otherwise
//      * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
//      */
//     function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
//         (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
//         _throwError(error, errorArg);
//         return recovered;
//     }

//     /**
//      * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
//      *
//      * See https://eips.ethereum.org/EIPS/eip-2098[ERC-2098 short signatures]
//      */
//     function tryRecover(
//         bytes32 hash,
//         bytes32 r,
//         bytes32 vs
//     ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
//         unchecked {
//             bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
//             // We do not check for an overflow here since the shift operation results in 0 or 1.
//             uint8 v = uint8((uint256(vs) >> 255) + 27);
//             return tryRecover(hash, v, r, s);
//         }
//     }

//     /**
//      * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
//      */
//     function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
//         (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, r, vs);
//         _throwError(error, errorArg);
//         return recovered;
//     }

//     /**
//      * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
//      * `r` and `s` signature fields separately.
//      */
//     function tryRecover(
//         bytes32 hash,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
//         // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
//         // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
//         // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
//         // signatures from current libraries generate a unique signature with an s-value in the lower half order.
//         //
//         // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
//         // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
//         // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
//         // these malleable signatures as well.
//         if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
//             return (address(0), RecoverError.InvalidSignatureS, s);
//         }

//         // If the signature is valid (and not malleable), return the signer address
//         address signer = ecrecover(hash, v, r, s);
//         if (signer == address(0)) {
//             return (address(0), RecoverError.InvalidSignature, bytes32(0));
//         }

//         return (signer, RecoverError.NoError, bytes32(0));
//     }

//     /**
//      * @dev Overload of {ECDSA-recover} that receives the `v`,
//      * `r` and `s` signature fields separately.
//      */
//     function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
//         (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
//         _throwError(error, errorArg);
//         return recovered;
//     }

//     /**
//      * @dev Optionally reverts with the corresponding custom error according to the `error` argument provided.
//      */
//     function _throwError(RecoverError error, bytes32 errorArg) private pure {
//         if (error == RecoverError.NoError) {
//             return; // no error: do nothing
//         } else if (error == RecoverError.InvalidSignature) {
//             revert ECDSAInvalidSignature();
//         } else if (error == RecoverError.InvalidSignatureLength) {
//             revert ECDSAInvalidSignatureLength(uint256(errorArg));
//         } else if (error == RecoverError.InvalidSignatureS) {
//             revert ECDSAInvalidSignatureS(errorArg);
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts/utils/introspection/IERC165.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/IERC165.sol)

// /**
//  * @dev Interface of the ERC-165 standard, as defined in the
//  * https://eips.ethereum.org/EIPS/eip-165[ERC].
//  *
//  * Implementers can declare support of contract interfaces, which can then be
//  * queried by others ({ERC165Checker}).
//  *
//  * For an implementation, see {ERC165}.
//  */
// interface IERC165 {
//     /**
//      * @dev Returns true if this contract implements the interface defined by
//      * `interfaceId`. See the corresponding
//      * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
//      * to learn more about how these ids are created.
//      *
//      * This function call must use less than 30 000 gas.
//      */
//     function supportsInterface(bytes4 interfaceId) external view returns (bool);
// }

// // node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol

// // OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

// /**
//  * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
//  * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
//  * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
//  * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
//  *
//  * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
//  * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
//  * case an upgrade adds a module that needs to be initialized.
//  *
//  * For example:
//  *
//  * [.hljs-theme-light.nopadding]
//  * ```solidity
//  * contract MyToken is ERC20Upgradeable {
//  *     function initialize() initializer public {
//  *         __ERC20_init("MyToken", "MTK");
//  *     }
//  * }
//  *
//  * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
//  *     function initializeV2() reinitializer(2) public {
//  *         __ERC20Permit_init("MyToken");
//  *     }
//  * }
//  * ```
//  *
//  * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
//  * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
//  *
//  * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
//  * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
//  *
//  * [CAUTION]
//  * ====
//  * Avoid leaving a contract uninitialized.
//  *
//  * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
//  * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
//  * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
//  *
//  * [.hljs-theme-light.nopadding]
//  * ```
//  * /// @custom:oz-upgrades-unsafe-allow constructor
//  * constructor() {
//  *     _disableInitializers();
//  * }
//  * ```
//  * ====
//  */
// abstract contract Initializable {
//     /**
//      * @dev Storage of the initializable contract.
//      *
//      * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
//      * when using with upgradeable contracts.
//      *
//      * @custom:storage-location erc7201:openzeppelin.storage.Initializable
//      */
//     struct InitializableStorage {
//         /**
//          * @dev Indicates that the contract has been initialized.
//          */
//         uint64 _initialized;
//         /**
//          * @dev Indicates that the contract is in the process of being initialized.
//          */
//         bool _initializing;
//     }

//     // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

//     /**
//      * @dev The contract is already initialized.
//      */
//     error InvalidInitialization();

//     /**
//      * @dev The contract is not initializing.
//      */
//     error NotInitializing();

//     /**
//      * @dev Triggered when the contract has been initialized or reinitialized.
//      */
//     event Initialized(uint64 version);

//     /**
//      * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
//      * `onlyInitializing` functions can be used to initialize parent contracts.
//      *
//      * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
//      * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
//      * production.
//      *
//      * Emits an {Initialized} event.
//      */
//     modifier initializer() {
//         // solhint-disable-next-line var-name-mixedcase
//         InitializableStorage storage $ = _getInitializableStorage();

//         // Cache values to avoid duplicated sloads
//         bool isTopLevelCall = !$._initializing;
//         uint64 initialized = $._initialized;

//         // Allowed calls:
//         // - initialSetup: the contract is not in the initializing state and no previous version was
//         //                 initialized
//         // - construction: the contract is initialized at version 1 (no reininitialization) and the
//         //                 current contract is just being deployed
//         bool initialSetup = initialized == 0 && isTopLevelCall;
//         bool construction = initialized == 1 && address(this).code.length == 0;

//         if (!initialSetup && !construction) {
//             revert InvalidInitialization();
//         }
//         $._initialized = 1;
//         if (isTopLevelCall) {
//             $._initializing = true;
//         }
//         _;
//         if (isTopLevelCall) {
//             $._initializing = false;
//             emit Initialized(1);
//         }
//     }

//     /**
//      * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
//      * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
//      * used to initialize parent contracts.
//      *
//      * A reinitializer may be used after the original initialization step. This is essential to configure modules that
//      * are added through upgrades and that require initialization.
//      *
//      * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
//      * cannot be nested. If one is invoked in the context of another, execution will revert.
//      *
//      * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
//      * a contract, executing them in the right order is up to the developer or operator.
//      *
//      * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
//      *
//      * Emits an {Initialized} event.
//      */
//     modifier reinitializer(uint64 version) {
//         // solhint-disable-next-line var-name-mixedcase
//         InitializableStorage storage $ = _getInitializableStorage();

//         if ($._initializing || $._initialized >= version) {
//             revert InvalidInitialization();
//         }
//         $._initialized = version;
//         $._initializing = true;
//         _;
//         $._initializing = false;
//         emit Initialized(version);
//     }

//     /**
//      * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
//      * {initializer} and {reinitializer} modifiers, directly or indirectly.
//      */
//     modifier onlyInitializing() {
//         _checkInitializing();
//         _;
//     }

//     /**
//      * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
//      */
//     function _checkInitializing() internal view virtual {
//         if (!_isInitializing()) {
//             revert NotInitializing();
//         }
//     }

//     /**
//      * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
//      * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
//      * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
//      * through proxies.
//      *
//      * Emits an {Initialized} event the first time it is successfully executed.
//      */
//     function _disableInitializers() internal virtual {
//         // solhint-disable-next-line var-name-mixedcase
//         InitializableStorage storage $ = _getInitializableStorage();

//         if ($._initializing) {
//             revert InvalidInitialization();
//         }
//         if ($._initialized != type(uint64).max) {
//             $._initialized = type(uint64).max;
//             emit Initialized(type(uint64).max);
//         }
//     }

//     /**
//      * @dev Returns the highest version that has been initialized. See {reinitializer}.
//      */
//     function _getInitializedVersion() internal view returns (uint64) {
//         return _getInitializableStorage()._initialized;
//     }

//     /**
//      * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
//      */
//     function _isInitializing() internal view returns (bool) {
//         return _getInitializableStorage()._initializing;
//     }

//     /**
//      * @dev Returns a pointer to the storage namespace.
//      */
//     // solhint-disable-next-line var-name-mixedcase
//     function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
//         assembly {
//             $.slot := INITIALIZABLE_STORAGE
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts/utils/Address.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/Address.sol)

// /**
//  * @dev Collection of functions related to the address type
//  */
// library Address {
//     /**
//      * @dev There's no code at `target` (it is not a contract).
//      */
//     error AddressEmptyCode(address target);

//     /**
//      * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
//      * `recipient`, forwarding all available gas and reverting on errors.
//      *
//      * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
//      * of certain opcodes, possibly making contracts go over the 2300 gas limit
//      * imposed by `transfer`, making them unable to receive funds via
//      * `transfer`. {sendValue} removes this limitation.
//      *
//      * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
//      *
//      * IMPORTANT: because control is transferred to `recipient`, care must be
//      * taken to not create reentrancy vulnerabilities. Consider using
//      * {ReentrancyGuard} or the
//      * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
//      */
//     function sendValue(address payable recipient, uint256 amount) internal {
//         if (address(this).balance < amount) {
//             revert Errors.InsufficientBalance(address(this).balance, amount);
//         }

//         (bool success, ) = recipient.call{value: amount}("");
//         if (!success) {
//             revert Errors.FailedCall();
//         }
//     }

//     /**
//      * @dev Performs a Solidity function call using a low level `call`. A
//      * plain `call` is an unsafe replacement for a function call: use this
//      * function instead.
//      *
//      * If `target` reverts with a revert reason or custom error, it is bubbled
//      * up by this function (like regular Solidity function calls). However, if
//      * the call reverted with no returned reason, this function reverts with a
//      * {Errors.FailedCall} error.
//      *
//      * Returns the raw returned data. To convert to the expected return value,
//      * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
//      *
//      * Requirements:
//      *
//      * - `target` must be a contract.
//      * - calling `target` with `data` must not revert.
//      */
//     function functionCall(address target, bytes memory data) internal returns (bytes memory) {
//         return functionCallWithValue(target, data, 0);
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
//      * but also transferring `value` wei to `target`.
//      *
//      * Requirements:
//      *
//      * - the calling contract must have an ETH balance of at least `value`.
//      * - the called Solidity function must be `payable`.
//      */
//     function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
//         if (address(this).balance < value) {
//             revert Errors.InsufficientBalance(address(this).balance, value);
//         }
//         (bool success, bytes memory returndata) = target.call{value: value}(data);
//         return verifyCallResultFromTarget(target, success, returndata);
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
//      * but performing a static call.
//      */
//     function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
//         (bool success, bytes memory returndata) = target.staticcall(data);
//         return verifyCallResultFromTarget(target, success, returndata);
//     }

//     /**
//      * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
//      * but performing a delegate call.
//      */
//     function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
//         (bool success, bytes memory returndata) = target.delegatecall(data);
//         return verifyCallResultFromTarget(target, success, returndata);
//     }

//     /**
//      * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
//      * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
//      * of an unsuccessful call.
//      */
//     function verifyCallResultFromTarget(
//         address target,
//         bool success,
//         bytes memory returndata
//     ) internal view returns (bytes memory) {
//         if (!success) {
//             _revert(returndata);
//         } else {
//             // only check if target is a contract if the call was successful and the return data is empty
//             // otherwise we already know that it was a contract
//             if (returndata.length == 0 && target.code.length == 0) {
//                 revert AddressEmptyCode(target);
//             }
//             return returndata;
//         }
//     }

//     /**
//      * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
//      * revert reason or with a default {Errors.FailedCall} error.
//      */
//     function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
//         if (!success) {
//             _revert(returndata);
//         } else {
//             return returndata;
//         }
//     }

//     /**
//      * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
//      */
//     function _revert(bytes memory returndata) private pure {
//         // Look for revert reason and bubble it up if present
//         if (returndata.length > 0) {
//             // The easiest way to bubble the revert reason is using memory via assembly
//             assembly ("memory-safe") {
//                 let returndata_size := mload(returndata)
//                 revert(add(32, returndata), returndata_size)
//             }
//         } else {
//             revert Errors.FailedCall();
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol

// // OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

// /**
//  * @dev Provides information about the current execution context, including the
//  * sender of the transaction and its data. While these are generally available
//  * via msg.sender and msg.data, they should not be accessed in such a direct
//  * manner, since when dealing with meta-transactions the account sending and
//  * paying for execution may not be the actual sender (as far as an application
//  * is concerned).
//  *
//  * This contract is only required for intermediate, library-like contracts.
//  */
// abstract contract ContextUpgradeable is Initializable {
//     function __Context_init() internal onlyInitializing {
//     }

//     function __Context_init_unchained() internal onlyInitializing {
//     }
//     function _msgSender() internal view virtual returns (address) {
//         return msg.sender;
//     }

//     function _msgData() internal view virtual returns (bytes calldata) {
//         return msg.data;
//     }

//     function _contextSuffixLength() internal view virtual returns (uint256) {
//         return 0;
//     }
// }

// // node_modules/@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

// /**
//  * @dev Contract module that helps prevent reentrant calls to a function.
//  *
//  * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
//  * available, which can be applied to functions to make sure there are no nested
//  * (reentrant) calls to them.
//  *
//  * Note that because there is a single `nonReentrant` guard, functions marked as
//  * `nonReentrant` may not call one another. This can be worked around by making
//  * those functions `private`, and then adding `external` `nonReentrant` entry
//  * points to them.
//  *
//  * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
//  * consider using {ReentrancyGuardTransient} instead.
//  *
//  * TIP: If you would like to learn more about reentrancy and alternative ways
//  * to protect against it, check out our blog post
//  * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
//  */
// abstract contract ReentrancyGuardUpgradeable is Initializable {
//     // Booleans are more expensive than uint256 or any type that takes up a full
//     // word because each write operation emits an extra SLOAD to first read the
//     // slot's contents, replace the bits taken up by the boolean, and then write
//     // back. This is the compiler's defense against contract upgrades and
//     // pointer aliasing, and it cannot be disabled.

//     // The values being non-zero value makes deployment a bit more expensive,
//     // but in exchange the refund on every call to nonReentrant will be lower in
//     // amount. Since refunds are capped to a percentage of the total
//     // transaction's gas, it is best to keep them low in cases like this one, to
//     // increase the likelihood of the full refund coming into effect.
//     uint256 private constant NOT_ENTERED = 1;
//     uint256 private constant ENTERED = 2;

//     /// @custom:storage-location erc7201:openzeppelin.storage.ReentrancyGuard
//     struct ReentrancyGuardStorage {
//         uint256 _status;
//     }

//     // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant ReentrancyGuardStorageLocation = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

//     function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
//         assembly {
//             $.slot := ReentrancyGuardStorageLocation
//         }
//     }

//     /**
//      * @dev Unauthorized reentrant call.
//      */
//     error ReentrancyGuardReentrantCall();

//     function __ReentrancyGuard_init() internal onlyInitializing {
//         __ReentrancyGuard_init_unchained();
//     }

//     function __ReentrancyGuard_init_unchained() internal onlyInitializing {
//         ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
//         $._status = NOT_ENTERED;
//     }

//     /**
//      * @dev Prevents a contract from calling itself, directly or indirectly.
//      * Calling a `nonReentrant` function from another `nonReentrant`
//      * function is not supported. It is possible to prevent this from happening
//      * by making the `nonReentrant` function external, and making it call a
//      * `private` function that does the actual work.
//      */
//     modifier nonReentrant() {
//         _nonReentrantBefore();
//         _;
//         _nonReentrantAfter();
//     }

//     function _nonReentrantBefore() private {
//         ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
//         // On the first call to nonReentrant, _status will be NOT_ENTERED
//         if ($._status == ENTERED) {
//             revert ReentrancyGuardReentrantCall();
//         }

//         // Any calls to nonReentrant after this point will fail
//         $._status = ENTERED;
//     }

//     function _nonReentrantAfter() private {
//         ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
//         // By storing the original value once again, a refund is triggered (see
//         // https://eips.ethereum.org/EIPS/eip-2200)
//         $._status = NOT_ENTERED;
//     }

//     /**
//      * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
//      * `nonReentrant` function in the call stack.
//      */
//     function _reentrancyGuardEntered() internal view returns (bool) {
//         ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
//         return $._status == ENTERED;
//     }
// }

// // contracts/lib/Helper.sol

// library HELPER {
//     function GET_IMAGE_ID_FROM_ATTESTATION(bytes memory data) internal pure returns (bytes32) {
//         (, , bytes memory PCR0, bytes memory PCR1, bytes memory PCR2, , , ) = abi.decode(
//             data,
//             (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256)
//         );

//         return GET_IMAGE_ID_FROM_PCRS(PCR0, PCR1, PCR2);
//     }

//     function GET_IMAGE_ID_FROM_PCRS(bytes calldata pcrs) internal pure returns (bytes32) {
//         (bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) = abi.decode(pcrs, (bytes, bytes, bytes));
//         return GET_IMAGE_ID_FROM_PCRS(PCR0, PCR1, PCR2);
//     }

//     function GET_IMAGE_ID_FROM_PCRS(bytes memory PCR0, bytes memory PCR1, bytes memory PCR2) internal pure returns (bytes32) {
//         bytes32 imageId = keccak256(abi.encodePacked(PCR0, PCR1, PCR2));
//         return imageId;
//     }

//     function GET_PUBKEY_AND_ADDRESS(bytes memory data) internal pure returns (bytes memory, address) {
//         (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

//         return (enclaveEciesKey, PUBKEY_TO_ADDRESS(enclaveEciesKey));
//     }

//     function GET_PUBKEY(bytes memory data) internal pure returns (bytes memory) {
//         (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

//         return (enclaveEciesKey);
//     }

//     function GET_ADDRESS(bytes memory data) internal pure returns (address) {
//         (, bytes memory enclaveEciesKey, , , , , , ) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

//         return (PUBKEY_TO_ADDRESS(enclaveEciesKey));
//     }

//     function PUBKEY_TO_ADDRESS(bytes memory publicKey) internal pure returns (address) {
//         // Ensure the internal key is 64 bytes long
//         if (publicKey.length != 64) {
//             revert Error.InvalidEnclaveKey();
//         }

//         // Perform the elliptic curve recover operation to get the Ethereum address
//         bytes32 hash = keccak256(publicKey);
//         return address(uint160(uint256(hash)));
//     }

//     function GET_ETH_SIGNED_HASHED_MESSAGE(bytes32 messageHash) internal pure returns (bytes32) {
//         return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
//     }

//     function GET_TIMESTAMP_IN_SEC_FROM_ATTESTATION(bytes memory data) internal pure returns (uint256) {
//         (, , , , , , , uint256 timestamp) = abi.decode(data, (bytes, bytes, bytes, bytes, bytes, uint256, uint256, uint256));

//         return timestamp / 1000;
//     }

//     function IS_ENCLAVE(bytes32 imageId) internal pure returns (bool) {
//         return !(imageId == bytes32(0) || imageId == NO_ENCLAVE_ID);
//     }

//     /**
//      * @notice Checks if addressToVerify posses access to enclave
//      */
//     function VERIFY_ENCLAVE_SIGNATURE(
//         bytes memory attestationData,
//         bytes calldata enclaveSignature,
//         address addressToVerify
//     ) internal pure {
//         bytes32 messageHash = keccak256(abi.encode(attestationData, addressToVerify));
//         bytes32 ethSignedMessageHash = GET_ETH_SIGNED_HASHED_MESSAGE(messageHash);

//         address signer = ECDSA.recover(ethSignedMessageHash, enclaveSignature);
//         if (signer != GET_ADDRESS(attestationData)) {
//             revert Error.InvalidEnclaveSignature(signer);
//         }
//     }

//     function MATCHING_ENGINE_FAMILY_ID(bytes32 roleId) internal pure returns (bytes32) {
//         return keccak256(abi.encode(roleId));
//     }

//     function PROVER_FAMILY_ID(uint256 marketId) internal pure returns (bytes32) {
//         return keccak256(abi.encode("prov", marketId));
//     }

//     function IVS_FAMILY_ID(uint256 marketId) internal pure returns (bytes32) {
//         return keccak256(abi.encode("ivs", marketId));
//     }

//     bytes32 internal constant NO_ENCLAVE_ID = 0xcd2e66bf0b91eeedc6c648ae9335a78d7c9a4ab0ef33612a824d91cdc68a4f21;

//     uint256 internal constant ACCEPTABLE_ATTESTATION_DELAY = 60000; // 60 seconds, 60,000 milliseconds
// }

// // contracts/periphery/AttestationAutherUpgradeable.sol

// contract AttestationAutherUpgradeable is
//     Initializable // initializer
// {
//     /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
//     IAttestationVerifier public immutable ATTESTATION_VERIFIER;

//     /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
//     uint256 public immutable ATTESTATION_MAX_AGE;

//     /// @custom:oz-upgrades-unsafe-allow constructor
//     constructor(IAttestationVerifier attestationVerifier, uint256 maxAge) {
//         ATTESTATION_VERIFIER = attestationVerifier;
//         ATTESTATION_MAX_AGE = maxAge;
//     }

//     struct EnclaveImage {
//         bytes PCR0;
//         bytes PCR1;
//         bytes PCR2;
//     }

//     /// @custom:storage-location erc7201:marlin.oyster.storage.AttestationAuther
//     struct AttestationAutherStorage {
//         mapping(bytes32 => EnclaveImage) whitelistedImages;
//         mapping(address => bytes32) verifiedKeys;
//         mapping(bytes32 => mapping(bytes32 => bool)) imageFamilies;
//     }

//     // keccak256(abi.encode(uint256(keccak256("marlin.oyster.storage.AttestationAuther")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant AttestationAutherStorageLocation =
//         0xc17b4b708b6f44255c20913a9d97a05300b670342c71fe5ae5b617bd4db55000;

//     function _getAttestationAutherStorage() private pure returns (AttestationAutherStorage storage $) {
//         assembly {
//             $.slot := AttestationAutherStorageLocation
//         }
//     }

//     error AttestationAutherPubkeyLengthInvalid();
//     error AttestationAutherPCRsInvalid();
//     error AttestationAutherImageNotWhitelisted();
//     error AttestationAutherImageNotInFamily();
//     error AttestationAutherKeyNotVerified();
//     error AttestationAutherAttestationTooOld();
//     error AttestationAutherMismatchedLengths();

//     event EnclaveImageWhitelisted(bytes32 indexed imageId, bytes PCR0, bytes PCR1, bytes PCR2);
//     event EnclaveImageRevoked(bytes32 indexed imageId);
//     event EnclaveImageAddedToFamily(bytes32 indexed imageId, bytes32 family);
//     event EnclaveImageRemovedFromFamily(bytes32 indexed imageId, bytes32 family);
//     event EnclaveKeyWhitelisted(bytes indexed enclavePubKey, bytes32 indexed imageId);
//     event EnclaveKeyRevoked(bytes indexed enclavePubKey);
//     event EnclaveKeyVerified(bytes indexed enclavePubKey, bytes32 indexed imageId);

//     function __AttestationAuther_init_unchained(EnclaveImage[] memory images) internal onlyInitializing {
//         for (uint256 i = 0; i < images.length; i++) {
//             _whitelistEnclaveImage(images[i]);
//         }
//     }

//     function __AttestationAuther_init_unchained(
//         EnclaveImage[] memory images,
//         bytes32[] memory families
//     ) internal onlyInitializing {
//         if (!(images.length == families.length)) revert AttestationAutherMismatchedLengths();
//         for (uint256 i = 0; i < images.length; i++) {
//             (bytes32 imageId,) = _whitelistEnclaveImage(images[i]);
//             _addEnclaveImageToFamily(imageId, families[i]);
//         }
//     }

//     function _pubKeyToAddress(bytes memory pubKey) internal pure returns (address) {
//         if (!(pubKey.length == 64)) revert AttestationAutherPubkeyLengthInvalid();

//         bytes32 hash = keccak256(pubKey);
//         return address(uint160(uint256(hash)));
//     }

//     function _whitelistEnclaveImage(EnclaveImage memory image) internal virtual returns (bytes32, bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         if (!(image.PCR0.length == 48 && image.PCR1.length == 48 && image.PCR2.length == 48))
//             revert AttestationAutherPCRsInvalid();

//         bytes32 imageId = keccak256(abi.encodePacked(image.PCR0, image.PCR1, image.PCR2));
//         if (!($.whitelistedImages[imageId].PCR0.length == 0)) return (imageId, false);

//         $.whitelistedImages[imageId] = EnclaveImage(image.PCR0, image.PCR1, image.PCR2);
//         emit EnclaveImageWhitelisted(imageId, image.PCR0, image.PCR1, image.PCR2);

//         return (imageId, true);
//     }

//     function _revokeEnclaveImage(bytes32 imageId) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         if (!($.whitelistedImages[imageId].PCR0.length != 0)) return false;

//         delete $.whitelistedImages[imageId];
//         emit EnclaveImageRevoked(imageId);

//         return true;
//     }

//     function _addEnclaveImageToFamily(bytes32 imageId, bytes32 family) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         if (!($.imageFamilies[family][imageId] == false)) return false;

//         $.imageFamilies[family][imageId] = true;
//         emit EnclaveImageAddedToFamily(imageId, family);

//         return true;
//     }

//     function _removeEnclaveImageFromFamily(bytes32 imageId, bytes32 family) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         if (!($.imageFamilies[family][imageId] == true)) return false;

//         $.imageFamilies[family][imageId] = false;
//         emit EnclaveImageRemovedFromFamily(imageId, family);

//         return true;
//     }

//     function _whitelistEnclaveKey(bytes memory enclavePubKey, bytes32 imageId) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();

//         address enclaveKey = _pubKeyToAddress(enclavePubKey);
//         if (!($.verifiedKeys[enclaveKey] == bytes32(0))) return false;

//         $.verifiedKeys[enclaveKey] = imageId;
//         emit EnclaveKeyWhitelisted(enclavePubKey, imageId);

//         return true;
//     }

//     function _revokeEnclaveKey(bytes memory enclavePubKey) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         address enclaveKey = _pubKeyToAddress(enclavePubKey);
//         if (!($.verifiedKeys[enclaveKey] != bytes32(0))) return false;

//         delete $.verifiedKeys[enclaveKey];
//         emit EnclaveKeyRevoked(enclavePubKey);

//         return true;
//     }

//     function _verifyEnclaveKey(bytes memory signature, IAttestationVerifier.Attestation memory attestation) internal virtual returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         bytes32 imageId = keccak256(abi.encodePacked(attestation.PCR0, attestation.PCR1, attestation.PCR2));
//         if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
//         if (!(attestation.timestampInMilliseconds / 1000 > block.timestamp - ATTESTATION_MAX_AGE))
//             revert AttestationAutherAttestationTooOld();

//         ATTESTATION_VERIFIER.verify(signature, attestation);

//         address enclaveKey = _pubKeyToAddress(attestation.enclavePubKey);
//         if (!($.verifiedKeys[enclaveKey] == bytes32(0))) return false;

//         $.verifiedKeys[enclaveKey] = imageId;
//         emit EnclaveKeyVerified(attestation.enclavePubKey, imageId);

//         return true;
//     }

//     function verifyEnclaveKey(bytes memory signature, IAttestationVerifier.Attestation memory attestation) external returns (bool) {
//         return _verifyEnclaveKey(signature, attestation);
//     }

//     function _allowOnlyVerified(address key) internal virtual view {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         bytes32 imageId = $.verifiedKeys[key];
//         if (!(imageId != bytes32(0))) revert AttestationAutherKeyNotVerified();
//         if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
//     }

//     function _allowOnlyVerifiedFamily(address key, bytes32 family) internal virtual view {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         bytes32 imageId = $.verifiedKeys[key];
//         if (!(imageId != bytes32(0))) revert AttestationAutherKeyNotVerified();
//         if (!($.whitelistedImages[imageId].PCR0.length != 0)) revert AttestationAutherImageNotWhitelisted();
//         if (!($.imageFamilies[family][imageId])) revert AttestationAutherImageNotInFamily();
//     }

//     function getWhitelistedImage(bytes32 _imageId) external view returns (EnclaveImage memory) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         return $.whitelistedImages[_imageId];
//     }

//     function getVerifiedKey(address _key) external view returns (bytes32) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         return $.verifiedKeys[_key];
//     }

//     function isImageInFamily(bytes32 imageId, bytes32 family) external view returns (bool) {
//         AttestationAutherStorage storage $ = _getAttestationAutherStorage();

//         return $.imageFamilies[family][imageId];
//     }
// }

// // node_modules/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/ERC165.sol)

// /**
//  * @dev Implementation of the {IERC165} interface.
//  *
//  * Contracts that want to implement ERC-165 should inherit from this contract and override {supportsInterface} to check
//  * for the additional interface id that will be supported. For example:
//  *
//  * ```solidity
//  * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
//  *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
//  * }
//  * ```
//  */
// abstract contract ERC165Upgradeable is Initializable, IERC165 {
//     function __ERC165_init() internal onlyInitializing {
//     }

//     function __ERC165_init_unchained() internal onlyInitializing {
//     }
//     /**
//      * @dev See {IERC165-supportsInterface}.
//      */
//     function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
//         return interfaceId == type(IERC165).interfaceId;
//     }
// }

// // node_modules/@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (proxy/ERC1967/ERC1967Utils.sol)

// /**
//  * @dev This library provides getters and event emitting update functions for
//  * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
//  */
// library ERC1967Utils {
//     /**
//      * @dev Storage slot with the address of the current implementation.
//      * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
//      */
//     // solhint-disable-next-line private-vars-leading-underscore
//     bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

//     /**
//      * @dev The `implementation` of the proxy is invalid.
//      */
//     error ERC1967InvalidImplementation(address implementation);

//     /**
//      * @dev The `admin` of the proxy is invalid.
//      */
//     error ERC1967InvalidAdmin(address admin);

//     /**
//      * @dev The `beacon` of the proxy is invalid.
//      */
//     error ERC1967InvalidBeacon(address beacon);

//     /**
//      * @dev An upgrade function sees `msg.value > 0` that may be lost.
//      */
//     error ERC1967NonPayable();

//     /**
//      * @dev Returns the current implementation address.
//      */
//     function getImplementation() internal view returns (address) {
//         return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
//     }

//     /**
//      * @dev Stores a new address in the ERC-1967 implementation slot.
//      */
//     function _setImplementation(address newImplementation) private {
//         if (newImplementation.code.length == 0) {
//             revert ERC1967InvalidImplementation(newImplementation);
//         }
//         StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
//     }

//     /**
//      * @dev Performs implementation upgrade with additional setup call if data is nonempty.
//      * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
//      * to avoid stuck value in the contract.
//      *
//      * Emits an {IERC1967-Upgraded} event.
//      */
//     function upgradeToAndCall(address newImplementation, bytes memory data) internal {
//         _setImplementation(newImplementation);
//         emit IERC1967.Upgraded(newImplementation);

//         if (data.length > 0) {
//             Address.functionDelegateCall(newImplementation, data);
//         } else {
//             _checkNonPayable();
//         }
//     }

//     /**
//      * @dev Storage slot with the admin of the contract.
//      * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
//      */
//     // solhint-disable-next-line private-vars-leading-underscore
//     bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

//     /**
//      * @dev Returns the current admin.
//      *
//      * TIP: To get this value clients can read directly from the storage slot shown below (specified by ERC-1967) using
//      * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
//      * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
//      */
//     function getAdmin() internal view returns (address) {
//         return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
//     }

//     /**
//      * @dev Stores a new address in the ERC-1967 admin slot.
//      */
//     function _setAdmin(address newAdmin) private {
//         if (newAdmin == address(0)) {
//             revert ERC1967InvalidAdmin(address(0));
//         }
//         StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
//     }

//     /**
//      * @dev Changes the admin of the proxy.
//      *
//      * Emits an {IERC1967-AdminChanged} event.
//      */
//     function changeAdmin(address newAdmin) internal {
//         emit IERC1967.AdminChanged(getAdmin(), newAdmin);
//         _setAdmin(newAdmin);
//     }

//     /**
//      * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
//      * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
//      */
//     // solhint-disable-next-line private-vars-leading-underscore
//     bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

//     /**
//      * @dev Returns the current beacon.
//      */
//     function getBeacon() internal view returns (address) {
//         return StorageSlot.getAddressSlot(BEACON_SLOT).value;
//     }

//     /**
//      * @dev Stores a new beacon in the ERC-1967 beacon slot.
//      */
//     function _setBeacon(address newBeacon) private {
//         if (newBeacon.code.length == 0) {
//             revert ERC1967InvalidBeacon(newBeacon);
//         }

//         StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

//         address beaconImplementation = IBeacon(newBeacon).implementation();
//         if (beaconImplementation.code.length == 0) {
//             revert ERC1967InvalidImplementation(beaconImplementation);
//         }
//     }

//     /**
//      * @dev Change the beacon and trigger a setup call if data is nonempty.
//      * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
//      * to avoid stuck value in the contract.
//      *
//      * Emits an {IERC1967-BeaconUpgraded} event.
//      *
//      * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
//      * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
//      * efficiency.
//      */
//     function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
//         _setBeacon(newBeacon);
//         emit IERC1967.BeaconUpgraded(newBeacon);

//         if (data.length > 0) {
//             Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
//         } else {
//             _checkNonPayable();
//         }
//     }

//     /**
//      * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
//      * if an upgrade doesn't perform an initialization call.
//      */
//     function _checkNonPayable() private {
//         if (msg.value > 0) {
//             revert ERC1967NonPayable();
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol

// // OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

// /**
//  * @dev Contract module that allows children to implement role-based access
//  * control mechanisms. This is a lightweight version that doesn't allow enumerating role
//  * members except through off-chain means by accessing the contract event logs. Some
//  * applications may benefit from on-chain enumerability, for those cases see
//  * {AccessControlEnumerable}.
//  *
//  * Roles are referred to by their `bytes32` identifier. These should be exposed
//  * in the external API and be unique. The best way to achieve this is by
//  * using `public constant` hash digests:
//  *
//  * ```solidity
//  * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
//  * ```
//  *
//  * Roles can be used to represent a set of permissions. To restrict access to a
//  * function call, use {hasRole}:
//  *
//  * ```solidity
//  * function foo() public {
//  *     require(hasRole(MY_ROLE, msg.sender));
//  *     ...
//  * }
//  * ```
//  *
//  * Roles can be granted and revoked dynamically via the {grantRole} and
//  * {revokeRole} functions. Each role has an associated admin role, and only
//  * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
//  *
//  * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
//  * that only accounts with this role will be able to grant or revoke other
//  * roles. More complex role relationships can be created by using
//  * {_setRoleAdmin}.
//  *
//  * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
//  * grant and revoke this role. Extra precautions should be taken to secure
//  * accounts that have been granted it. We recommend using {AccessControlDefaultAdminRules}
//  * to enforce additional security measures for this role.
//  */
// abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable, IAccessControl, ERC165Upgradeable {
//     struct RoleData {
//         mapping(address account => bool) hasRole;
//         bytes32 adminRole;
//     }

//     bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

//     /// @custom:storage-location erc7201:openzeppelin.storage.AccessControl
//     struct AccessControlStorage {
//         mapping(bytes32 role => RoleData) _roles;
//     }

//     // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant AccessControlStorageLocation = 0x02dd7bc7dec4dceedda775e58dd541e08a116c6c53815c0bd028192f7b626800;

//     function _getAccessControlStorage() private pure returns (AccessControlStorage storage $) {
//         assembly {
//             $.slot := AccessControlStorageLocation
//         }
//     }

//     /**
//      * @dev Modifier that checks that an account has a specific role. Reverts
//      * with an {AccessControlUnauthorizedAccount} error including the required role.
//      */
//     modifier onlyRole(bytes32 role) {
//         _checkRole(role);
//         _;
//     }

//     function __AccessControl_init() internal onlyInitializing {
//     }

//     function __AccessControl_init_unchained() internal onlyInitializing {
//     }
//     /**
//      * @dev See {IERC165-supportsInterface}.
//      */
//     function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
//         return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
//     }

//     /**
//      * @dev Returns `true` if `account` has been granted `role`.
//      */
//     function hasRole(bytes32 role, address account) public view virtual returns (bool) {
//         AccessControlStorage storage $ = _getAccessControlStorage();
//         return $._roles[role].hasRole[account];
//     }

//     /**
//      * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
//      * is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier.
//      */
//     function _checkRole(bytes32 role) internal view virtual {
//         _checkRole(role, _msgSender());
//     }

//     /**
//      * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
//      * is missing `role`.
//      */
//     function _checkRole(bytes32 role, address account) internal view virtual {
//         if (!hasRole(role, account)) {
//             revert AccessControlUnauthorizedAccount(account, role);
//         }
//     }

//     /**
//      * @dev Returns the admin role that controls `role`. See {grantRole} and
//      * {revokeRole}.
//      *
//      * To change a role's admin, use {_setRoleAdmin}.
//      */
//     function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
//         AccessControlStorage storage $ = _getAccessControlStorage();
//         return $._roles[role].adminRole;
//     }

//     /**
//      * @dev Grants `role` to `account`.
//      *
//      * If `account` had not been already granted `role`, emits a {RoleGranted}
//      * event.
//      *
//      * Requirements:
//      *
//      * - the caller must have ``role``'s admin role.
//      *
//      * May emit a {RoleGranted} event.
//      */
//     function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
//         _grantRole(role, account);
//     }

//     /**
//      * @dev Revokes `role` from `account`.
//      *
//      * If `account` had been granted `role`, emits a {RoleRevoked} event.
//      *
//      * Requirements:
//      *
//      * - the caller must have ``role``'s admin role.
//      *
//      * May emit a {RoleRevoked} event.
//      */
//     function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
//         _revokeRole(role, account);
//     }

//     /**
//      * @dev Revokes `role` from the calling account.
//      *
//      * Roles are often managed via {grantRole} and {revokeRole}: this function's
//      * purpose is to provide a mechanism for accounts to lose their privileges
//      * if they are compromised (such as when a trusted device is misplaced).
//      *
//      * If the calling account had been revoked `role`, emits a {RoleRevoked}
//      * event.
//      *
//      * Requirements:
//      *
//      * - the caller must be `callerConfirmation`.
//      *
//      * May emit a {RoleRevoked} event.
//      */
//     function renounceRole(bytes32 role, address callerConfirmation) public virtual {
//         if (callerConfirmation != _msgSender()) {
//             revert AccessControlBadConfirmation();
//         }

//         _revokeRole(role, callerConfirmation);
//     }

//     /**
//      * @dev Sets `adminRole` as ``role``'s admin role.
//      *
//      * Emits a {RoleAdminChanged} event.
//      */
//     function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
//         AccessControlStorage storage $ = _getAccessControlStorage();
//         bytes32 previousAdminRole = getRoleAdmin(role);
//         $._roles[role].adminRole = adminRole;
//         emit RoleAdminChanged(role, previousAdminRole, adminRole);
//     }

//     /**
//      * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
//      *
//      * Internal function without access restriction.
//      *
//      * May emit a {RoleGranted} event.
//      */
//     function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
//         AccessControlStorage storage $ = _getAccessControlStorage();
//         if (!hasRole(role, account)) {
//             $._roles[role].hasRole[account] = true;
//             emit RoleGranted(role, account, _msgSender());
//             return true;
//         } else {
//             return false;
//         }
//     }

//     /**
//      * @dev Attempts to revoke `role` to `account` and returns a boolean indicating if `role` was revoked.
//      *
//      * Internal function without access restriction.
//      *
//      * May emit a {RoleRevoked} event.
//      */
//     function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
//         AccessControlStorage storage $ = _getAccessControlStorage();
//         if (hasRole(role, account)) {
//             $._roles[role].hasRole[account] = false;
//             emit RoleRevoked(role, account, _msgSender());
//             return true;
//         } else {
//             return false;
//         }
//     }
// }

// // node_modules/@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol

// // OpenZeppelin Contracts (last updated v5.1.0) (proxy/utils/UUPSUpgradeable.sol)

// /**
//  * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
//  * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
//  *
//  * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
//  * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
//  * `UUPSUpgradeable` with a custom implementation of upgrades.
//  *
//  * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
//  */
// abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
//     /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
//     address private immutable __self = address(this);

//     /**
//      * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
//      * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
//      * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
//      * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
//      * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
//      * during an upgrade.
//      */
//     string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

//     /**
//      * @dev The call is from an unauthorized context.
//      */
//     error UUPSUnauthorizedCallContext();

//     /**
//      * @dev The storage `slot` is unsupported as a UUID.
//      */
//     error UUPSUnsupportedProxiableUUID(bytes32 slot);

//     /**
//      * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
//      * a proxy contract with an implementation (as defined in ERC-1967) pointing to self. This should only be the case
//      * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
//      * function through ERC-1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
//      * fail.
//      */
//     modifier onlyProxy() {
//         _checkProxy();
//         _;
//     }

//     /**
//      * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
//      * callable on the implementing contract but not through proxies.
//      */
//     modifier notDelegated() {
//         _checkNotDelegated();
//         _;
//     }

//     function __UUPSUpgradeable_init() internal onlyInitializing {
//     }

//     function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
//     }
//     /**
//      * @dev Implementation of the ERC-1822 {proxiableUUID} function. This returns the storage slot used by the
//      * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
//      *
//      * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
//      * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
//      * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
//      */
//     function proxiableUUID() external view virtual notDelegated returns (bytes32) {
//         return ERC1967Utils.IMPLEMENTATION_SLOT;
//     }

//     /**
//      * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
//      * encoded in `data`.
//      *
//      * Calls {_authorizeUpgrade}.
//      *
//      * Emits an {Upgraded} event.
//      *
//      * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
//      */
//     function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
//         _authorizeUpgrade(newImplementation);
//         _upgradeToAndCallUUPS(newImplementation, data);
//     }

//     /**
//      * @dev Reverts if the execution is not performed via delegatecall or the execution
//      * context is not of a proxy with an ERC-1967 compliant implementation pointing to self.
//      * See {_onlyProxy}.
//      */
//     function _checkProxy() internal view virtual {
//         if (
//             address(this) == __self || // Must be called through delegatecall
//             ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
//         ) {
//             revert UUPSUnauthorizedCallContext();
//         }
//     }

//     /**
//      * @dev Reverts if the execution is performed via delegatecall.
//      * See {notDelegated}.
//      */
//     function _checkNotDelegated() internal view virtual {
//         if (address(this) != __self) {
//             // Must not be called through delegatecall
//             revert UUPSUnauthorizedCallContext();
//         }
//     }

//     /**
//      * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
//      * {upgradeToAndCall}.
//      *
//      * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
//      *
//      * ```solidity
//      * function _authorizeUpgrade(address) internal onlyOwner {}
//      * ```
//      */
//     function _authorizeUpgrade(address newImplementation) internal virtual;

//     /**
//      * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
//      *
//      * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
//      * is expected to be the implementation slot in ERC-1967.
//      *
//      * Emits an {IERC1967-Upgraded} event.
//      */
//     function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
//         try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
//             if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
//                 revert UUPSUnsupportedProxiableUUID(slot);
//             }
//             ERC1967Utils.upgradeToAndCall(newImplementation, data);
//         } catch {
//             // The implementation is not UUPS
//             revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
//         }
//     }
// }

// // contracts/EntityKeyRegistry.sol

// contract EntityKeyRegistry is
//     Initializable,
//     ContextUpgradeable,
//     ERC165Upgradeable,
//     AccessControlUpgradeable,
//     UUPSUpgradeable,
//     ReentrancyGuardUpgradeable,
//     AttestationAutherUpgradeable
// {
//     using HELPER for bytes;
//     using HELPER for bytes32;

//     //---------------------------------------- Event start ----------------------------------------//

//     event UpdateKey(address indexed user, uint256 indexed keyIndex);
//     event RemoveKey(address indexed user, uint256 indexed keyIndex);
//     event ImageBlacklisted(bytes32 indexed imageId);

//     //---------------------------------------- Event end ----------------------------------------//

//     //---------------------------------------- Constant start ----------------------------------------//

//     bytes32 public constant KEY_REGISTER_ROLE = keccak256("KEY_REGISTER_ROLE");
//     bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

//     //---------------------------------------- Constant end ----------------------------------------//

//     //---------------------------------------- State Variable start ----------------------------------------//

//     mapping(address => mapping(uint256 => bytes)) public pub_key;
//     mapping(bytes32 => bool) public blackListedImages;

//     // in case we add more contracts in the inheritance chain
//     uint256[500] private __gap_0;

//     //---------------------------------------- State Variable start ----------------------------------------//

//     //---------------------------------------- Init start ----------------------------------------//

//     /// @custom:oz-upgrades-unsafe-allow constructor
//     constructor(IAttestationVerifier _av) AttestationAutherUpgradeable(_av, HELPER.ACCEPTABLE_ATTESTATION_DELAY) initializer {}

//     function initialize(address _admin, EnclaveImage[] calldata _initWhitelistImages) public initializer {
//         __Context_init_unchained();
//         __ERC165_init_unchained();
//         __AccessControl_init_unchained();
//         __UUPSUpgradeable_init_unchained();

//         _grantRole(DEFAULT_ADMIN_ROLE, _admin);
//         _setRoleAdmin(MODERATOR_ROLE, DEFAULT_ADMIN_ROLE);

//         __AttestationAuther_init_unchained(_initWhitelistImages);
//     }

//     //---------------------------------------- Init end ----------------------------------------//

//     function addProverManager(address _proverManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
//         _grantRole(KEY_REGISTER_ROLE, _proverManager);
//     }

//     /**
//      * @notice Ads a new user after verification
//      */
//     function updatePubkey(
//         address _keyOwner,
//         uint256 _keyIndex,
//         bytes calldata _pubkey,
//         bytes calldata _attestationData
//     ) external onlyRole(KEY_REGISTER_ROLE) {
//         if (_pubkey.length != 64) {
//             revert Error.InvalidEnclaveKey();
//         }

//         pub_key[_keyOwner][_keyIndex] = _pubkey;

//         _verifyKeyInternal(_attestationData);

//         emit UpdateKey(_keyOwner, _keyIndex);
//     }

//     /**
//      * @notice Verifies a new key against enclave
//      */
//     function verifyKey(bytes calldata _attestationData) external onlyRole(KEY_REGISTER_ROLE) {
//         _verifyKeyInternal(_attestationData);
//     }

//     /**
//      * @notice Whitelist a new image. Called when a market creator creates a new market
//      */
//     function whitelistImageUsingPcrs(bytes32 _family, bytes calldata _pcrs) external onlyRole(KEY_REGISTER_ROLE) {
//         (bytes memory pcr0, bytes memory pcr1, bytes memory pcr2) = abi.decode(_pcrs, (bytes, bytes, bytes));

//         _whitelistImageIfNot(_family, pcr0, pcr1, pcr2);
//     }

//     function _verifyKeyInternal(bytes calldata _data) internal {
//         (
//             bytes memory attestation,
//             bytes memory enclaveKey,
//             bytes memory pcr0,
//             bytes memory pcr1,
//             bytes memory pcr2,
//             uint256 timestamp
//         ) = abi.decode(_data, (bytes, bytes, bytes, bytes, bytes, uint256));

//         bool isVerified = _verifyEnclaveKey(attestation, IAttestationVerifier.Attestation(enclaveKey, pcr0, pcr1, pcr2, timestamp));
//         if (!isVerified) {
//             revert Error.EnclaveKeyNotVerified();
//         }
//     }

//     function _whitelistImageIfNot(bytes32 _family, bytes memory _pcr0, bytes memory _pcr1, bytes memory _pcr2) internal {
//         bytes32 imageId = _pcr0.GET_IMAGE_ID_FROM_PCRS(_pcr1, _pcr2);
//         if (!imageId.IS_ENCLAVE()) {
//             revert Error.MustBeAnEnclave(imageId);
//         }

//         if (blackListedImages[imageId]) {
//             revert Error.BlacklistedImage(imageId);
//         }
//         (bytes32 inferredImageId, ) = _whitelistEnclaveImage(EnclaveImage(_pcr0, _pcr1, _pcr2));

//         // inferredImage == false && isVerified == x, invalid image, revert
//         if (inferredImageId != imageId) {
//             revert Error.InferredImageIdIsDifferent();
//         }
//         _addEnclaveImageToFamily(imageId, _family);
//     }

//     /**
//      * @notice Removes an existing pubkey
//      */
//     function removePubkey(address _keyOwner, uint256 _keyIndex) external onlyRole(KEY_REGISTER_ROLE) {
//         delete pub_key[_keyOwner][_keyIndex];

//         emit RemoveKey(_keyOwner, _keyIndex);
//     }

//     function allowOnlyVerifiedFamily(bytes32 _familyId, address _key) external view {
//         return _allowOnlyVerifiedFamily(_key, _familyId);
//     }

//     function removeEnclaveImageFromFamily(bytes32 _imageId, bytes32 _family) external onlyRole(KEY_REGISTER_ROLE) {
//         _removeEnclaveImageFromFamily(_imageId, _family);
//     }

//     // ---------- SECURITY FEATURE FUNCTIONS ----------- //
//     function blacklistImage(bytes32 _imageId) external onlyRole(MODERATOR_ROLE) {
//         if (blackListedImages[_imageId]) {
//             revert Error.AlreadyABlacklistedImage(_imageId);
//         }
//         blackListedImages[_imageId] = true;
//         emit ImageBlacklisted(_imageId);
//         _revokeEnclaveImage(_imageId);
//     }

//     //-------------------------------- Overrides start --------------------------------//

//     function supportsInterface(
//         bytes4 _interfaceId
//     ) public view virtual override(ERC165Upgradeable, AccessControlUpgradeable) returns (bool) {
//         return super.supportsInterface(_interfaceId);
//     }

//     function _authorizeUpgrade(address /*account*/) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

//     //---------------------------------------- Override end ----------------------------------------//

// }

