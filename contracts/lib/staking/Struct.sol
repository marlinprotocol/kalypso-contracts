// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Struct {

    /* Job Manager */
    struct JobInfo {
        address requester;
        address operator;
        uint256 feePaid;
        uint256 deadline;
    }

    /* Staking Pool */
    struct PoolLockInfo {
        address token;
        uint256 amount;
        address transmitter;
    }

    /* NativeStaking */
    struct NativeStakingLock {
        address token;
        uint256 amount;
    }

    struct JobSlashed {
        uint256 jobId;
        address operator; // TODO: check if cheaper than pulling from JobManager
        address rewardAddress;
    }

    struct SnapshotTxCountInfo {
        uint256 idxToSubmit; // idx of pratial snapshot tx to submit
        uint256 numOfTxs; // total number of txs for the snapshot
    }

    /*==================== Symbiotic Staking ==================== */

    /* Snapshot Submission */
    struct VaultSnapshot {
        address operator;
        address vault;
        address stakeToken;
        uint256 stakeAmount;
    }

    struct ConfirmedTimestamp {
        uint256 captureTimestamp;
        address transmitter;
        uint256 transmitterComissionRate;
    }

    // struct OperatorSnapshot {
    //     address operator;
    //     address[] stakeTokens;
    //     uint256[] stakeAmounts;
    // }

    /* Job Lock */
    struct SymbioticStakingLock {
        address stakeToken;
        uint256 amount;
        // transmitter who submitted with confirmedTimestamp used when job is created
        address transmitter; 
    }

    struct PoolConfig {
        uint256 weight;
        bool enabled;
    }
    struct RewardPerToken {
        uint256 value;
        uint256 lastUpdatedTimestamp; //? not sure if this actually saves gas
    }
}