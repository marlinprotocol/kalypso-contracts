// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVault {
    function slasher() external view returns (address);
    function collateral() external view returns (address);
}