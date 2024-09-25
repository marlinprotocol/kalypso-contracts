// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "../staking/IStakingPool.sol";

interface INativeStaking is IStakingPool {

    // TODO: check if timestamp is needed
    event Staked(address indexed account, address indexed operator, address indexed token, uint256 amount, uint256 timestamp);
    event SelfStaked(address indexed operator, address indexed token, uint256 amount, uint256 timestamp);
    event StakeWithdrawn(address indexed account, address indexed operator, address indexed token, uint256 amount, uint256 timestamp);
    event SelfStakeWithdrawn(address indexed operator, address indexed token, uint256 amount, uint256 timestamp);

    // function stakeOf(address _operator, address _token) external view returns (uint256);

    // function stakesOf(address _operator) external view returns (address[] memory _tokens, uint256[] memory _amounts);
    
    // function isSupportedSignature(bytes4 sig) external view returns (bool);
}