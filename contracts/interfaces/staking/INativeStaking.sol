// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "../staking/IStakingPool.sol";

interface INativeStaking is IStakingPool {

    /*====================================================== events =======================================================*/

    event Staked(address indexed account, address indexed operator, address indexed token, uint256 amount);

    event StakeWithdrawalRequested(address indexed account, address indexed operator, address indexed token, uint256 index, uint256 amount);

    event StakeWithdrawn(address indexed account, address indexed operator, address indexed token, uint256 index, uint256 amount);

    event WithdrawalDurationSet(uint256 indexed duration);

    /*===================================================== functions =====================================================*/
    function stake(address stakeToken, address operator, uint256 amount) external;

    function requestStakeWithdrawal(address operator, address stakeToken, uint256 amount) external;

    function withdrawStake(address operator, uint256[] calldata index) external;
}
