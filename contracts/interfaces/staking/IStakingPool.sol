// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Struct} from "../../lib/staking/Struct.sol";

interface IStakingPool {
    function isSupportedStakeToken(address stakeToken) external view returns (bool);

    function lockStake(uint256 jobId, address operator) external; // Staking Manager only

    function onJobCompletion(uint256 jobId, address operator, uint256 feeRewardAmount, uint256 inflationRewardAmount, uint256 timestampIdx) external; // Staking Manager only

    function slash(Struct.JobSlashed[] calldata slashedJobs) external; // Staking Manager only  

    function getOperatorStakeAmount(address stakeToken, address operator) external view returns (uint256);

    function getOperatorActiveStakeAmount(address stakeToken, address operator) external view returns (uint256);

    function rewardDistributor() external view returns (address);

    function distributeInflationReward(address operator, uint256 rewardAmount, uint256 timestampIdx) external; // Staking Manager only

    function getStakeTokenList() external view returns (address[] memory);

    function getStakeTokenWeights() external view returns (address[] memory, uint256[] memory);

    function tokenSelectionWeightSum() external view returns (uint256);

    function getStakeAmount(address stakeToken, address staker, address operator) external view returns (uint256);
}