// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Struct} from "../../lib/staking/Struct.sol";

interface IStakingPool {
    function isSupportedStakeToken(address _token) external view returns (bool);

    function lockStake(uint256 _jobId, address _operator) external; // Staking Manager only

    function onJobCompletion(uint256 _jobId, address _operator, uint256 _feeRewardAmount, uint256 _inflationRewardAmount) external; // Staking Manager only

    function slash(Struct.JobSlashed[] calldata _slashedJobs) external; // Staking Manager only  

    function getOperatorStakeAmount(address _operator, address _token) external view returns (uint256);

    function getOperatorActiveStakeAmount(address _operator, address _token) external view returns (uint256);

    function rewardDistributor() external view returns (address);

    function distributeInflationReward(address _operator, uint256 _rewardAmount) external; // Staking Manager only

    function getStakeTokenList() external view returns (address[] memory);

    function getStakeAmount(address staker, address stakeToken, address operator) external view returns (uint256);
}