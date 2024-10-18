// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/staking/Struct.sol";

pragma solidity ^0.8.26;

interface IStakingManager {
    function onJobCreation(uint256 jobId, address operator) external;

    function onJobCompletion(uint256 jobId, address operator, uint256 feePaid) external;

    function onSlashResult(Struct.JobSlashed[] calldata slashedJobs) external;

    // function distributeInflationReward(address operator, uint256 rewardAmount, uint256 timestampIdx) external;

    function getPoolConfig(address pool) external view returns (Struct.PoolConfig memory);
}