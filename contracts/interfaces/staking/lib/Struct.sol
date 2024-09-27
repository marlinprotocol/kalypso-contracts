// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Struct {
    struct PoolLockInfo {
        address token;
        uint256 amount;
        address transmitter;
    }

    struct NativeStakingLock {
        address token;
        uint256 amount;
    }

    struct JobSlashed {
        uint256 jobId;
        address operator;
        address rewardAddress;
    }

    struct SnapshotTxCountInfo {
        uint256 idxToSubmit; // idx of pratial snapshot tx to submit
        uint256 numOfTxs; // total number of txs for the snapshot
    }

    struct VaultSnapshot {
        address operator;
        address vault;
        address token;
        uint256 stake;
    }

    struct ConfirmedTimestamp {
        uint256 captureTimestamp;
        address transmitter;
        uint256 transmitterComissionRate;
    }
}