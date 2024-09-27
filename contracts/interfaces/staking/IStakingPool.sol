// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Struct} from "./lib/Struct.sol";

interface IStakingPool {
    function isSupportedToken(address _token) external view returns (bool);

    // function getPoolStake(address _operator, address _token) external view returns (uint256);

    function lockStake(uint256 _jobId, address _operator) external; // Staking Manager only

    function unlockStake(uint256 _jobId, address _operator) external; // Staking Manager only

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external; // Staking Manager only  
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