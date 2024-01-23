// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// import "./interfaces/IPriorityLog.sol";

/// Optional contract to be used by request creator where
/// he can set on what priority his requests should be processed by matching engine
contract PriorityLog {
    enum Priority {
        NONE,
        COST,
        TIME,
        DEADLINE
    }

    mapping(address => Priority) public priorityStore;

    function setPriority(Priority priority) external {
        address _msgSender = msg.sender;
        priorityStore[_msgSender] = priority;
    }
}
