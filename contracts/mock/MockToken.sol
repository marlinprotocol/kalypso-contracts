// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(address _admin, uint256 _totalSupply) ERC20("MockToken", "MT") {
        _mint(_admin, _totalSupply);
    }
}
