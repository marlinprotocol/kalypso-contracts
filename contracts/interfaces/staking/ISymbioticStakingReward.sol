// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/staking/Struct.sol";

pragma solidity ^0.8.26;

interface ISymbioticStakingReward {

    /*====================================================== events =======================================================*/

    event RewardDistributed(address indexed stakeToken, address indexed operator, uint256 amount);

    event RewardClaimed(address indexed operator, uint256 amount);

    event StakingPoolSet(address indexed stakingPool);

    event JobManagerSet(address indexed jobManager);

    event SymbioticStakingSet(address indexed symbioticStaking);

    event FeeRewardTokenSet(address indexed feeRewardToken);

    event RewardAccrued(address indexed rewardToken, address indexed vault, uint256 amount);

    event RewardPerTokenUpdated(address indexed stakeToken, address indexed rewardToken, address indexed operator, uint256 rewardPerTokenStoredUpdated, uint256 rewardPerTokenAdded);

    /*===================================================== functions =====================================================*/

    function rewardPerTokenPaid(address _stakeToken, address _rewardToken, address _vault, address _operator) external view returns (uint256);

    function rewardPerTokenStored(address _stakeToken, address _rewardToken, address _operator) external view returns (uint256);

    function rewardAccrued(address _rewardToken, address _vault) external view returns (uint256);

    function claimReward(address _operator) external;

    function updateFeeReward(address _stakeToken, address _operator, uint256 _amount) external;

    function onSnapshotSubmission(address _vault, address _operator) external;
}