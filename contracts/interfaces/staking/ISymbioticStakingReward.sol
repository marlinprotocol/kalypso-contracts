// SPDX-License-Identifier: MIT

import {Struct} from "../../lib/Struct.sol";

pragma solidity ^0.8.26;

interface ISymbioticStakingReward {

    /*====================================================== events =======================================================*/

    event RewardDistributed(address indexed stakeToken, address indexed prover, uint256 amount);

    event RewardClaimed(address indexed prover, uint256 amount);

    event StakingPoolSet(address indexed stakingPool);

    event ProofMarketplaceSet(address indexed proofMarketplace);

    event SymbioticStakingSet(address indexed symbioticStaking);

    event FeeRewardTokenSet(address indexed feeRewardToken);

    event RewardAccrued(address indexed rewardToken, address indexed vault, uint256 amount);

    event RewardPerTokenUpdated(address indexed stakeToken, address indexed rewardToken, address indexed prover, uint256 rewardPerTokenStoredUpdated, uint256 rewardPerTokenAdded);

    /*===================================================== functions =====================================================*/

    function rewardPerTokenPaid(address _stakeToken, address _rewardToken, address _vault, address _prover) external view returns (uint256);

    function rewardPerTokenStored(address _stakeToken, address _rewardToken, address _prover) external view returns (uint256);

    function rewardAccrued(address _rewardToken, address _vault) external view returns (uint256);

    function claimReward(address _prover) external;

    function updateFeeReward(address _stakeToken, address _prover, uint256 _amount) external;

    function onSnapshotSubmission(address _vault, address _prover) external;
}