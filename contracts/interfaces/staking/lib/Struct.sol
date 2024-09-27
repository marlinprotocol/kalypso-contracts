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
}