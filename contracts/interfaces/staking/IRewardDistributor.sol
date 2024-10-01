// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IRewardDistributor {
    function addFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function addInflationReward(address _operator, uint256 _amount) external; 
}