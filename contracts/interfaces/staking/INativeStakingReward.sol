// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface INativeStakingReward {
    function update(address account, address _stakeToken, address _operator) external;
}