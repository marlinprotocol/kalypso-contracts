// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

library Error {
    string public constant ONLY_ADMIN_CAN_CALL = "1";
    string public constant CANNOT_BE_SAME = "2";
    string public constant ALREADY_EXISTS = "3";
    string public constant CANNOT_BE_ZERO = "4";
    string public constant DOES_NOT_EXISTS = "5";

    string public constant SHOULD_BE_IN_CREATE_STATE = "6";
    string public constant HAS_A_PENDING_WORK = "7";

    string public constant ONLY_TO_IDLE_GENERATORS = "8";

    string public constant INVALID_PROOF = "9";
    string public constant SHOULD_BE_IN_ASSIGNED_STATE = "10";

    string public constant SHOULD_BE_IN_CROSSED_DEADLINE_STATE = "11";
    string public constant INVALID_GENERATOR = "12";

    string public constant CAN_N0T_BE_SLASHED = "13";
    string public constant ONLY_WORKING_GENERATORS = "14";

    string public constant INSUFFICIENT_REWARD = "15";

    string public constant SHOULD_BE_IN_EXPIRED_STATE = "16";
}
