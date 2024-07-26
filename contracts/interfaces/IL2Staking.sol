// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IL2Staking {
    function stake(address generatorAddress, uint256 amount) external returns (uint256);

    function intendToReduceStake(uint256 stakeToReduce) external;

    function unstake(address receiver) external;
}
