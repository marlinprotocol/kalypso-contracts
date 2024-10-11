// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Struct {

    /*=========================== Job Manager =============================*/
    struct JobInfo {
        address requester;
        address operator;
        uint256 feePaid;
        uint256 deadline;
    }

    /*========================= Staking Manager ===========================*/

    struct PoolConfig {
        uint256 share;
        bool enabled;
    }

    /*=========================== Staking Pool ============================*/

    struct PoolLockInfo {
        address token;
        uint256 amount;
        address transmitter;
    }

    /*========================== Native Staking ===========================*/

    struct NativeStakingLock {
        address token;
        uint256 amount;
    }

    struct JobSlashed {
        uint256 jobId;
        address operator; // TODO: check if cheaper than pulling from JobManager
        address rewardAddress;
    }

    struct WithdrawalRequest {
        address stakeToken;
        uint256 amount;
        uint256 withdrawalTime;
    }

    /*========================= Symbiotic Staking =========================*/

    struct VaultSnapshot {
        address operator;
        address vault;
        address stakeToken;
        uint256 stakeAmount;
    }

    struct SnapshotTxCountInfo {
        uint256 idxToSubmit; // idx of pratial snapshot tx to submit
        uint256 numOfTxs; // total number of txs for the snapshot
    }

    struct ConfirmedTimestamp {
        uint256 captureTimestamp;
        address transmitter;
        uint256 transmitterComissionRate;
    }

    struct SymbioticStakingLock {
        address stakeToken;
        uint256 amount;
    }
}