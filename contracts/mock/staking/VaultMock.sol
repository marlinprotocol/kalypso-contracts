// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/staking/symbiotic/IVault.sol";

contract VaultMock is IVault {
    address private _collateral;
    address private _slasher;

    constructor(address collateral) {
        _collateral = collateral;
    }

    function setSlasher(address slasher) external {
        _slasher = slasher;
    }

    function slasher() external view override returns (address) {
        return _slasher;
    }

    function collateral() external view override returns (address) {
        return _collateral;
    }
}