// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IProverCallbacks {
    event AddedStake(address indexed proverAddress, address indexed token, uint256 amount);
    function addStakeCallback(address proverAddress, address token, uint256 amount) external;

    event IntendToReduceStake(address indexed proverAddress, address indexed token, uint256 amount);
    function intendToReduceStakeCallback(address proverAddress, address token, uint256 amount) external;

    event RemovedStake(address indexed proverAddress, address indexed token, uint256 amount);
    function removeStakeCallback(address proverAddress, address token, uint256 amount) external;

    event StakeLockImposed(address indexed proverAddress, address indexed token, uint256 stake);
    function stakeLockImposedCallback(address proverAddress, address token, uint256 amount) external;

    event StakeLockReleased(address indexed proverAddress, address indexed token, uint256 stake);
    function stakeLockReleasedCallback(address proverAddress, address token, uint256 amount) external;

    event StakeSlashed(address indexed proverAddress, address indexed token, uint256 stake);
    function stakeSlashedCallback(address proverAddress, address token, uint256 amount) external;

    event SymbioticCompleteSnapshot(uint256 indexed captureTimestamp);
    function symbioticCompleteSnapshotCallback(uint256 captureTimestamp) external;

    event RequestStakeDecrease(address indexed proverAddress, address indexed token, uint256 amount);
}
