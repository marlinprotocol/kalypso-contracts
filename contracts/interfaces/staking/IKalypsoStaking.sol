// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IKalypsoStaking {
    function isSupportedToken(address _token) external view returns (bool);

    function getPoolStake(address _operator, address _token) external view returns (uint256);

    function lockStake(uint256 _jobId, address _token, uint256 _selfStakeLock, uint256 _delegatedStakeLock) external; // Staking Manager only

    struct PoolLockInfo {
        address token;
        uint256 amount;
        address transmitter;
    }

    // struct NativeStakingLock {
    //     address token;
    //     uint256 amount;
    // }
}