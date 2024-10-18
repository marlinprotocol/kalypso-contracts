// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/staking/Struct.sol";

pragma solidity ^0.8.26;

interface ISymbioticStakingReward {

    /*====================================================== events =======================================================*/

    event RewardDistributed(address indexed stakeToken, address indexed operator, uint256 amount);

    event RewardClaimed(address indexed operator, uint256 amount);

    event StakingPoolSet(address indexed stakingPool);

    event JobManagerSet(address indexed jobManager);

    event FeeRewardTokenSet(address indexed feeRewardToken);

    /*===================================================== functions =====================================================*/

    function claimReward(address _operator) external;

    function updateFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function onSnapshotSubmission(address _vault, address _operator) external;
}