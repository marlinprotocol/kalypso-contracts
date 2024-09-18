// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IStakingManager {
    function onJobCreation(uint256 jobId, address operator, address token, uint256 amountToLock) external;

    function onJobCompletion(uint256 jobId, address token) external;

    function submitProofs(uint256[] memory jobIds, bytes[] calldata proofs) external;

    function submitProof(uint256 jobId, bytes calldata proof) external;

    function setStakingManager(address _stakingManager) external;
}