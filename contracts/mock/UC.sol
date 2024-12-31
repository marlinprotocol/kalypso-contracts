// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

contract UC is Initializable, ContextUpgradeable, ERC165Upgradeable, UUPSUpgradeable {
    // gaps in case we new vars in same file
    uint256[500] private __gap_0;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address /*account*/) internal view override {}

    uint256 public slot1;

    function initialize() public virtual initializer {}

    function my_operation1() public virtual returns (uint256) {
        return slot1;
    }

    // ---- other operations below ---- ///

    function my_operation2() public virtual {}

    // gaps in case we new vars in same file
    uint256[50] private __gap_1;
}
