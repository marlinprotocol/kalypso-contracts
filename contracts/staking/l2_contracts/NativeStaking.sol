// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NativeStaking {
    using EnumerableSet for EnumerableSet.AddressSet;

    error UnsupportedToken();

    // TODO: token Set
    EnumerableSet.AddressSet private tokens;

    // TODO: checkpoints?

    mapping(address operator => mapping(address token => uint256 amount)) public stakes;

    modifier onlySupportedToken(address _token) {
        require(tokens.contains(_token), UnsupportedToken());
        _;
    }

    // Returns the amount of a token staked by the operator
    function stakeOf(address _operator, address _token) external view onlySupportedToken(_token) returns (uint256) {
        return stakes[_operator][_token];
    }

    //  Returns the list of tokens staked by the operator and the amounts
    function stakesOf(address _operator) external view returns (address[] memory _tokens, uint256[] memory _amounts) {
        uint256 len = tokens.length();

        for (uint256 i = 0; i < len; i++) {
            _tokens[i] = tokens.at(i);
            _amounts[i] = stakes[_operator][tokens.at(i)];
        }
    }

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
    function getStake(address account, address operator, address token) external view returns (uint256) {
        // TODO
    }

    // stake of an account for all operators
    function getStakes(address account, address token) external view returns (uint256) {
        // TODO
    }

    // TODO: manages the staking information and tokens provided by stakers and delegated to specific operators

    // TODO: functions that can provide the latest staking information for specific users and operators

    /*======================================== Admin ========================================*/

    function addToken(address token) external {
        // TODO: Admin only

        // TODO: token should be added in StakingManager as well
    }

    function removeToken(address token) external {
        // TODO: admin only

        // TODO: token should be added in StakingManager as well
    }
}
