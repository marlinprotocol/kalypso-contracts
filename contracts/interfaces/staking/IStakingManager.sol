// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/staking/Struct.sol";

pragma solidity ^0.8.26;

interface IStakingManager {
    /*===================================================== events ======================================================*/

    event StakingPoolAdded(address indexed pool);

    event StakingPoolRemoved(address indexed pool);

    event ProofMarketplaceSet(address indexed proofMarketplace);

    event SymbioticStakingSet(address indexed symbioticStaking);

    event FeeTokenSet(address indexed feeToken);

    event PoolEnabledSet(address indexed pool, bool enabled);

    event PoolRewardShareSet(address[] indexed pools, uint256[] shares);

    /*===================================================== functions =====================================================*/

    function onTaskAssignment(uint256 bidId, address prover) external;

    function onTaskCompletion(uint256 bidId, address prover, uint256 feePaid) external;

    function onSlashResult(Struct.TaskSlashed[] calldata slashedTasks) external;

    function getPoolConfig(address pool) external view returns (Struct.PoolConfig memory);
}