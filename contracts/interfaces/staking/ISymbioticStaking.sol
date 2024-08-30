// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISymbioticStaking {
    // function stakeOf(address _operator, address _token) external view returns (uint256);

    struct SnapshotTxCountInfo {
        uint256 count;
        uint256 length;
    }

    struct OperatorSnapshot {
        address operator;
        address token;
        uint256 stake;
    }

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
        address rewardAddress;
    }

    // event OperatorSnapshotSubmitted

    // event VaultSnapshotSubmitted

    // event SlashResultSubmitted

    // event SubmissionCompleted
}
