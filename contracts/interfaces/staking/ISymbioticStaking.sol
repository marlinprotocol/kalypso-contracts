// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "./IStakingPool.sol";

import {Struct} from "../../lib/staking/Struct.sol";

interface ISymbioticStaking is IStakingPool {
    /*====================================================== events =======================================================*/

    // TODO: temporary
    event VaultSnapshotSubmitted(
        address indexed transmitter, uint256 index, uint256 numOfTxs, bytes vaultSnapshotData, bytes signature
    );

    // TODO: temporary
    event SlashResultSubmitted(
        address indexed transmitter, uint256 index, uint256 numOfTxs, bytes slashResultData, bytes signature
    );

    event SubmissionCooldownSet(uint256 cooldown);

    event BaseTransmitterComissionRateSet(uint256 rate);

    event JobManagerSet(address jobManager);

    event RewardDistributorSet(address rewardDistributor);

    /*===================================================== functions =====================================================*/

    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes calldata _vaultSnapshotData,
        bytes calldata _signature
    ) external;

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        uint256 _captureTimestamp,
        bytes calldata _slashResultData,
        bytes calldata _signature
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

    /// @notice Returns the timestampIdx of latest completed snapshot submission
    function latestConfirmedTimestampIdx() external view returns (uint256);
}
