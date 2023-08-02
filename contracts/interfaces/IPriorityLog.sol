// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IPriorityLog {
    enum Priority {
        NONE,
        COST,
        TIME,
        DEADLINE
    }

    function priorityStore(address) external returns (Priority);

    function setPriority(Priority priority) external;
}
