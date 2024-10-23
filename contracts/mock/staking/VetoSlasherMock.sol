// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/staking/symbiotic/IVetoSlasher.sol";

contract VetoSlasherMock is IVetoSlasher {
    event VetoSlashRequestPlaced(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes hints);
    event VetoSlashExecuted(uint256 slashIndex, bytes hints);

    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external override {
        emit VetoSlashRequestPlaced(subnetwork, operator, amount, captureTimestamp, hints);
    }

    function executeSlash(
        uint256 slashIndex,
        bytes calldata hints
    ) external override {
        emit VetoSlashExecuted(slashIndex, hints);
    }
}