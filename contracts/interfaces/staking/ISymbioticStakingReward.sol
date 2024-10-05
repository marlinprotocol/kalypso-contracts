// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface ISymbioticStakingReward {
    function updateFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function updateInflationReward(address _operator, uint256 _rewardAmount) external;

    // function onStakeUpdate(address _account, address _stakeToken, address _operator) external;

    // function onClaimReward(address _account, address _operator) external;

    // function onSlash() external;

    // function setStakeToken(address _stakingPool, bool _isSupported) external;
}