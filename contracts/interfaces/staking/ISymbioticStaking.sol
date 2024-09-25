// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IKalypsoStaking} from "./IKalypsoStaking.sol";

interface ISymbioticStaking is IKalypsoStaking {
    // function stakeOf(address _operator, address _token) external view returns (uint256);

    struct SnapshotTxCountInfo {
        uint256 idxToSubmit; // idx of pratial snapshot tx to submit
        uint256 numOfTxs; // total number of txs for the snapshot
    }

    struct OperatorSnapshot {
        address operator;
        address token;
        uint256 stake;
    }
    
    //! TODO: add operator
    struct VaultSnapshot {
        address vault;
        address token;
        uint256 stake;
    }

    struct SlashResultData {
        uint256 jobId;
        SlashResult slashResult;
    }

    struct SlashResult {
        uint256 slashAmount;
        address rewardAddress; // address that transmitted slash reqeust to L1 Vault
    }

    struct ConfirmedTimestamp {
        uint256 capturedTimestamp;
        uint256 rewardShare; // TODO
        address transmitter;
    }

    // event OperatorSnapshotSubmitted

    // event VaultSnapshotSubmitted

    // event SlashResultSubmitted

    // event SubmissionCompleted

    /// @notice Returns the captureTimestamp of latest completed snapshot submission
    function lastConfirmedTimestamp() external view returns (uint256);
}
