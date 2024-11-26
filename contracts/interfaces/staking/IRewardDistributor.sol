// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IRewardDistributor {
    function updateFeeReward(address _stakeToken, address _prover, uint256 _rewardAmount) external;

    function updateInflationReward(address _prover, uint256 _rewardAmount) external;

    function onStakeUpdate(address _account, address _stakeToken, address _prover) external;

    function onClaimReward(address _account, address _prover) external;

    function onSlash() external;

    function setStakeToken(address _stakingPool, bool _isSupported) external;
}