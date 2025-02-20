// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/staking/symbiotic/IInstantSlasher.sol";

contract InstantSlasherMock is IInstantSlasher {
    address private _vault;

    event InstantSlashExecuted(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp, bytes hints);

    constructor(address vault) {
        _vault = vault;
    }

    function vault() external view override returns (address) {
        return _vault;
    }

    function slash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external override {
        emit InstantSlashExecuted(subnetwork, operator, amount, captureTimestamp, hints);
    }
}