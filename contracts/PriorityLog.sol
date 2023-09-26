// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./interfaces/IPriorityLog.sol";

/// Optional contract to be used by request creator where
/// he can set on what priority his requests should be processed by matching engine
contract PriorityLog is IPriorityLog {
    mapping(address => Priority) public override priorityStore;

    function setPriority(Priority priority) external override {
        address _msgSender = msg.sender;
        priorityStore[_msgSender] = priority;
    }
}
