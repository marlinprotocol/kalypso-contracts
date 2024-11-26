// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "./IStakingPool.sol";

import {Struct} from "../../lib/staking/Struct.sol";

interface ISymbioticStaking is IStakingPool {
    /*====================================================== events =======================================================*/

    event VaultSnapshotSubmitted(
        address indexed transmitter, uint256 indexed captureTimestamp, uint256 index, uint256 numOfTxs, bytes32 indexed imageId, bytes vaultSnapshotData, bytes proof
    );

    event SlashResultSubmitted(
        address indexed transmitter, uint256 indexed captureTimestamp, uint256 index, uint256 numOfTxs, bytes32 indexed imageId, bytes slashResultData, bytes proof
    );

    event SnapshotConfirmed(address indexed transmitter, uint256 confirmedTimestamp);

    event SubmissionCooldownSet(uint256 cooldown);

    event BaseTransmitterComissionRateSet(uint256 rate);

    event ProofMarketplaceSet(address proofMarketplace);

    event RewardDistributorSet(address rewardDistributor);

    event EnclaveImageAdded(bytes32 indexed imageId, bytes PCR0, bytes PCR1, bytes PCR2);

    event EnclaveImageRemoved(bytes32 indexed imageId);

    event AttestationVerifierSet(address attestationVerifier);

    /*===================================================== functions =====================================================*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes32 _imageId,
        bytes calldata _vaultSnapshotData,
        bytes calldata _proof
    ) external;

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes32 _imageId,
        bytes calldata _slashResultData,
        bytes calldata _proof
    ) external;

    function lockInfo(uint256 _jobId) external view returns (address stakeToken, uint256 amount);

    function txCountInfo(uint256 _captureTimestamp, bytes32 _type)
        external
        view
        returns (uint256 idxToSubmit, uint256 numOfTxs);

    function registeredTransmitters(uint256 _captureTimestamp) external view returns (address);

    function getSubmissionStatus(uint256 _captureTimestamp, address _transmitter) external view returns (bytes32);

    function confirmedTimestampInfo(uint256 _idx) external view returns (Struct.ConfirmedTimestamp memory);

    /// @notice Returns the captureTimestamp of latest completed snapshot submission
    function latestConfirmedTimestamp() external view returns (uint256);

    function latestConfirmedTimestampInfo() external view returns (Struct.ConfirmedTimestamp memory);

    /// @notice Returns the timestampIdx of latest completed snapshot submission
    function latestConfirmedTimestampIdx() external view returns (uint256);
}
