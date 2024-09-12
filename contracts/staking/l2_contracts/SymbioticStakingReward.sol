// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/* 
    Unlike common staking contracts, this contract is interacted each time snapshot is submitted to Symbiotic Staking,
    which means the state of each vault address will be updated whenvever snapshot is submitted.
*/

contract SymbioticStakingReward {
    //? what should be done when stake is locked?
    // -> just update totalStakeAmount and rewardPerToken?
    // -> does this even affect anything?

    // TODO: (mapping) captureTimestamp => token => vault => amount
    
    // TODO: (mapping) captureTimestamp => token => totalStakeAmount
    
    // TODO: (mapping) token => rewardPerToken
    
    // TODO: (array) confirmed timestamp

    // TODO: (function) function that updates confirmed timestamp
    // this should be called by StakingManager contract when partial txs are completed
    
    // TODO: (function) updates reward per token for each submission
    
    // TODO: admin

    // TODO: claim
}