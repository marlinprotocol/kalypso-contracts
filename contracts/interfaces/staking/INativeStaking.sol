// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStakingPool} from "../staking/IStakingPool.sol";

interface INativeStaking is IStakingPool {

    /*====================================================== events =======================================================*/

    event Staked(address indexed account, address indexed prover, address indexed token, uint256 amount);

    event StakeWithdrawalRequested(address indexed account, address indexed prover, address token, uint256 indexed index, uint256 amount);

    event StakeWithdrawn(address indexed account, address indexed prover, address token, uint256 indexed index, uint256 amount);

    event WithdrawalDurationSet(uint256 duration);

    /*===================================================== functions =====================================================*/
    function stake(address stakeToken, address prover, uint256 amount) external;

    function requestStakeWithdrawal(address prover, address stakeToken, uint256 amount) external;

    function withdrawStake(address prover, uint256[] calldata index) external;
}
