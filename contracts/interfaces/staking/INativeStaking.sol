// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "../staking/IStakingPool.sol";

interface INativeStaking is IStakingPool {

    function stake(address operator, address stakeToken, uint256 amount) external;

    // TODO: check if timestamp is needed
    event Staked(address indexed account, address indexed operator, address indexed token, uint256 amount, uint256 timestamp);
    event StakeWithdrawn(address indexed account, address indexed operator, address indexed token, uint256 amount, uint256 timestamp);
}