// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OpenMintToken is ERC20 {
    constructor() ERC20("Open Mint Token", "OMT") {}

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}