// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISymbioticStaking {
    // function stakeOf(address _operator, address _token) external view returns (uint256);

    struct SnapshotTxInfo {
        uint256 count;
        uint256 length;
    }

    struct OperatorSnapshot {
        address operator;
        uint256 stake;
    }

    struct VaultSnapshot {
        address vault;
        uint256 stake;
    }

    struct SlashResult {
        uint256 jobId;
        uint256 slashAmount;
        address rewardAddress;
    }
}
