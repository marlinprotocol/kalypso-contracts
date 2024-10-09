// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IInflationRewardManager {
    function updatePendingInflationReward(address _operator) external returns (uint256 pendingInflationReward);
}