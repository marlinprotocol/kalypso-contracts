// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {

    uint256 constant INITIAL_SUPPLY = 100_000_000 ether;

    constructor(address admin) ERC20("USDC", "USDC") {
        _mint(admin, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
