// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Struct} from "../../lib/Struct.sol";

interface IStakingPool {
    /*====================================================== events =======================================================*/

    /* Task */

    event StakeLocked(uint256 indexed bidId, address indexed prover, address indexed token, uint256 amount);

    event StakeUnlocked(uint256 indexed bidId, address indexed prover, address indexed token, uint256 amount);

    event TaskSlashed(uint256 indexed bidId, address indexed prover, address indexed token, uint256 amount);
    
    /* Stake Token */

    event StakeTokenAdded(address indexed token, uint256 indexed weight);

    event StakeTokenRemoved(address indexed token);

    event StakeTokenSelectionWeightSet(address indexed token, uint256 indexed weight);

    event AmountToLockSet(address indexed token, uint256 indexed amount);

    /* Contracts Set */

    event StakingManagerSet(address indexed stakingManager);

    event FeeRewardTokenSet(address indexed token);


    /*===================================================== functions =====================================================*/

    function lockStake(uint256 bidId, address prover) external;

    function onTaskCompletion(uint256 bidId, address prover, uint256 feeRewardAmount) external;

    function slash(Struct.TaskSlashed[] calldata slashedTasks) external;

    function rewardDistributor() external view returns (address);

    function getStakeTokenList() external view returns (address[] memory);
    
    function getStakeTokenWeights() external view returns (address[] memory, uint256[] memory);
    
    function stakeTokenSelectionWeightSum() external view returns (uint256);

    function isSupportedStakeToken(address stakeToken) external view returns (bool);

    function getProverStakeAmount(address stakeToken, address prover) external view returns (uint256);
    
    function getStakeAmount(address stakeToken, address staker, address prover) external view returns (uint256);

    function getProverActiveStakeAmount(address stakeToken, address prover) external view returns (uint256);

}