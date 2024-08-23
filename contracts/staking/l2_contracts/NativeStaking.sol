// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract NativeStaking {
    // TODO: token Set
    // TODO: checkpoints?

    // TODO: (getter) Operator => token => stakeAmount
    mapping(address operator => mapping(address token => uint256 amount)) public stakingAmounts;
    

    // Staker should be able to choose an Operator they want to stake into
    // This should update StakingManger's state
    function stake(address operator, address token, uint256 amount) external {
        // TODO: should accept only POND atm, but should have flexibility to accept other tokens

        //?: Will the rewards be tracked off-chain? Or tracked with Checkpoints?
    }

    // Operators need to self stake tokens to be able to receive jobs (jobs will be restricted based on self stake amount)
    // This should update StakingManger's state
    function selfStake(address _token, uint256 amount) external {
        // TODO: only operators
    }

    // This should update StakingManger's state
    function unstake(address operator, address token, uint256 amount) external {
        // TODO
    }

    /*======================================== Getters ========================================*/

    // stake of an account for a specific operator
    function stakeOf(address account, address operator, address token) external view returns (uint256) {
        // TODO
    }
    
    // stake of an account for all operators
    function stakeOf(address account, address token) external view returns (uint256) {
        // TODO
    }

    // TODO: manages the staking information and tokens provided by stakers and delegated to specific operators

    // TODO: functions that can provide the latest staking information for specific users and operators
    

    /*======================================== Admin ========================================*/

    function addToken(address token) external {
        // TODO: Admin only
    }

    function removeToken(address token) external {
        // TODO: admin only
    }
}