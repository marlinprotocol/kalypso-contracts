// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./UC.sol";

contract UC_with_rg is UC, ReentrancyGuardUpgradeable {
    uint256 private new_slot;
    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // no need to add it, but wrote for clarity
    function initialize() public override initializer {
        UC.initialize();
    }

    function my_operation1() public override nonReentrant returns (uint256) {
        return UC.my_operation1();
    }
}
