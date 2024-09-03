// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IKalypsoStaking {
    // function stakeOf(address _operator, address _token) external view returns (uint256);
    function isSupportedToken(address _token) external view returns (bool);

    function getStakeAmount(address _operator, address _token) external view returns (uint256);

    function getStakeAmountList(address _operator) external view returns (address[] memory _operators, uint256[] memory _amounts);

    function lockStake(address _operator, address _token, uint256 _amount) external; // Staking Manager only
}