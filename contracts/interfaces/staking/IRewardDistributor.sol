// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IRewardDistributor {
    function addReward(address _stakeToken, address operator, address _rewardToken, uint256 _amount) external;
}