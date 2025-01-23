// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInstantSlasher {
    function vault() external view returns (address);

    function slash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external;
}