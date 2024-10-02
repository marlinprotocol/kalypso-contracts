// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IRewardDistributor} from "./IRewardDistributor.sol";

interface INativeStakingReward is IRewardDistributor {
    function update(address account, address _stakeToken, address _operator) external;
}