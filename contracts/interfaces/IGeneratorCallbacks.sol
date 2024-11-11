// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IGeneratorCallbacks {
    event AddedStake(address indexed generatorAddress, address indexed token, uint256 amount);
    function addStakeCallback(address generatorAddress, address token, uint256 amount) external;

    event IntendToReduceStake(address indexed generatorAddress, address indexed token, uint256 amount);
    function intendToReduceStakeCallback(address generatorAddress, address token, uint256 amount) external;

    event RemovedStake(address indexed generatorAddress, address indexed token, uint256 amount);
    function removeStakeCallback(address generatorAddress, address token, uint256 amount) external;

    event StakeLockImposed(address indexed generatorAddress, address indexed token, uint256 stake);
    function stakeLockImposedCallback(address generatorAddress, address token, uint256 amount) external;

    event StakeLockReleased(address indexed generatorAddress, address indexed token, uint256 stake);
    function stakeLockReleasedCallback(address generatorAddress, address token, uint256 amount) external;

    event StakeSlashed(address indexed generatorAddress, address indexed token, uint256 stake);
    function stakeSlashedCallback(address generatorAddress, address token, uint256 amount) external;

    event SymbioticCompleteSnapshot(uint256 indexed captureTimestamp);
    function symbioticCompleteSnapshotCallback(uint256 captureTimestamp) external;

    event RequestStakeDecrease(address indexed generatorAddress, address indexed token, uint256 amount);
}
