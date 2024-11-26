// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Enum} from "../lib/Enum.sol";

/// Optional contract to be used by request creator where
/// he can set on what priority his requests should be processed by matching engine
contract PriorityLog {
    mapping(address => Enum.Priority) public priorityStore;

    function setPriority(Enum.Priority priority) external {
        address _msgSender = msg.sender;
        priorityStore[_msgSender] = priority;
    }
}
