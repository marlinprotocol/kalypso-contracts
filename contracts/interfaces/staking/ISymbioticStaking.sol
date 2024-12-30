// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "./IStakingPool.sol";
import {Struct} from "../../lib/Struct.sol";
import {Enum} from "../../lib/Enum.sol";

interface ISymbioticStaking is IStakingPool {

    /*====================================================== events =======================================================*/

    event VaultSnapshotSubmitted(
        address indexed transmitter, uint256 indexed captureTimestamp, uint256 index, uint256 numOfTxs, bytes32 indexed imageId, bytes vaultSnapshotData, bytes proof
    );
    event SlashResultSubmitted(
        address indexed transmitter, uint256 indexed captureTimestamp, uint256 index, uint256 numOfTxs, bytes32 indexed imageId, bytes slashResultData, bytes proof
    );
    event SnapshotConfirmed(address indexed transmitter, uint256 indexed confirmedTimestamp);
    event SubmissionCooldownSet(uint256 cooldown);
    event BaseTransmitterComissionRateSet(uint256 rate);
    event ProofMarketplaceSet(address proofMarketplace);
    event RewardDistributorSet(address rewardDistributor);
    event EnclaveImageAdded(bytes32 indexed imageId, bytes PCR0, bytes PCR1, bytes PCR2);
    event EnclaveImageRemoved(bytes32 indexed imageId);
    event AttestationVerifierSet(address attestationVerifier);

    /*===================================================== functions =====================================================*/

    function submitVaultSnapshot(
        uint256 index,
        uint256 numOfTxs, // number of total transactions
        uint256 captureTimestamp,
        bytes32 imageId,
        bytes calldata vaultSnapshotData,
        bytes calldata proof
    ) external;

    function submitSlashResult(
        uint256 index,
        uint256 numOfTxs, // number of total transactions
        uint256 captureTimestamp,
        uint256 lastBlockNumber,
        bytes32 imageId,
        bytes calldata slashResultData,
        bytes calldata proof
    ) external;

    function lockInfo(uint256 bidId) external view returns (address stakeToken, uint256 amount);

    function txCountInfo(uint256 captureTimestamp, bytes32 _txType) external view returns (uint256 idxToSubmit, uint256 numOfTxs);

    function getSubmissionStatus(uint256 captureTimestamp, address transmitter) external view returns (bytes32);

    function confirmedTimestampInfo(uint256 idx) external view returns (Struct.ConfirmedTimestamp memory);

    /// @notice Returns the captureTimestamp of latest completed snapshot submission
    function latestConfirmedTimestamp() external view returns (uint256);

    function latestConfirmedTimestampInfo() external view returns (Struct.ConfirmedTimestamp memory);

    /// @notice Returns the timestampIdx of latest completed snapshot submission
    function latestConfirmedTimestampIdx() external view returns (uint256);
}
