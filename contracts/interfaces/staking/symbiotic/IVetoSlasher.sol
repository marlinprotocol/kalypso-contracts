// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVetoSlasher {
    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external;

    function executeSlash(
        uint256 slashIndex,
        bytes calldata hints
    ) external;
}