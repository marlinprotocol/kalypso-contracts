// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IKalypsoStaking {
    function stakeOf(address _operator, address _token) external view returns (uint256);
}