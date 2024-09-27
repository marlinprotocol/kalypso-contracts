// SPDX-License-Identifier: MIT

import {Struct} from "./lib/Struct.sol";

pragma solidity ^0.8.26;

interface IStakingManager {
    function onJobCreation(uint256 jobId, address operator) external;

    function onJobCompletion(uint256 jobId, address operator) external;

    function onSlashResult(Struct.JobSlashed[] calldata slashedJobs) external;
}