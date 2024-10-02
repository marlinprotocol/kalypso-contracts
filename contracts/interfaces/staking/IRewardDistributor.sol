// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IRewardDistributor {
    function addFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function addInflationReward(address _operator, address[] calldata stakeTokens, uint256[] calldata rewardAmounts) external;

    function onStakeUpdate(address _account, address _stakeToken, address _operator) external;

    function onClaimReward(address _account, address _operator) external;

    function onSlash() external;
}