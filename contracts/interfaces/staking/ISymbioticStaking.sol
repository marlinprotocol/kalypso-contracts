// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "./IStakingPool.sol";

import {Struct} from "../../lib/staking/Struct.sol";    

interface ISymbioticStaking is IStakingPool {
    function submitVaultSnapshot(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        bytes calldata _vaultSnapshotData,
        bytes calldata _signature
    ) external;

    function submitSlashResult(
        uint256 _index,
        uint256 _numOfTxs, // number of total transactions
        bytes memory _slashResultData,
        bytes memory _signature
    ) external;

    function getTxCountInfo(uint256 _captureTimestamp, address _transmitter, bytes32 _type) external view returns (Struct.SnapshotTxCountInfo memory);

    function getSubmissionStatus(uint256 _captureTimestamp, address _transmitter) external view returns (bytes32);

    

    function confirmedTimestampInfo(uint256 _idx) external view returns (Struct.ConfirmedTimestamp memory);

    // event OperatorSnapshotSubmitted

    // event VaultSnapshotSubmitted

    // event SlashResultSubmitted

    // event SubmissionCompleted

    /// @notice Returns the captureTimestamp of latest completed snapshot submission
    function latestConfirmedTimestamp() external view returns (uint256);

    /// @notice Returns the timestampIdx of latest completed snapshot submission
    function latestConfirmedTimestampIdx() external view returns (uint256);
}
