// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

library Error {
    string public constant ONLY_ADMIN_CAN_CALL = "1";
    string public constant CANNOT_BE_ZERO = "2";
    string public constant GENERATOR_ALREADY_EXISTS = "3";
    string public constant CAN_NOT_LEAVE_WITH_ACTIVE_MARKET = "4";
    string public constant INVALID_GENERATOR = "5";
    string public constant CAN_NOT_WITHDRAW_MORE_UNLOCKED_AMOUNT = "6";
    string public constant INVALID_MARKET = "7";
    string public constant ALREADY_JOINED_MARKET = "8";
    string public constant CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE = "9";
    string public constant CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST = "10";
    string public constant CAN_N0T_BE_SLASHED = "11";
    string public constant ASSIGN_ONLY_TO_IDLE_GENERATORS = "12";
    string public constant INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE = "13";
    string public constant INSUFFICIENT_STAKE_TO_LOCK = "14";
    string public constant ONLY_WORKING_GENERATORS = "15";

    string public constant ENCLAVE_KEY_NOT_VERIFIED = "16";
    string public constant CAN_NOT_GRANT_ROLE_WITHOUT_ATTESTATION = "17";
    string public constant CANNOT_BE_ADMIN_LESS = "18";

    string public constant MARKET_ALREADY_EXISTS = "19";
    string public constant CAN_NOT_ASSIGN_EXPIRED_TASKS = "20";
    string public constant INVALID_INPUTS = "21";
    string public constant ARITY_MISMATCH = "22";
    string public constant ONLY_MATCHING_ENGINE_CAN_ASSIGN = "23";
    string public constant INVALID_TASK_ID = "24";
    string public constant SHOULD_BE_IN_CREATE_STATE = "25";
    string public constant PROOF_PRICE_MISMATCH = "26";
    string public constant PROOF_TIME_MISMATCH = "27";

    string public constant ONLY_EXPIRED_ASKS_CAN_BE_CANCELLED = "28";
    string public constant ONLY_ASSIGNED_ASKS_CAN_BE_PROVED = "29";
    string public constant INVALID_PROOF = "30";
    string public constant SHOULD_BE_IN_CROSSED_DEADLINE_STATE = "31";
    string public constant SHOULD_BE_IN_ASSIGNED_STATE = "32";
    string public constant ONLY_GENERATOR_CAN_DISCARD_REQUEST = "33";
    string public constant ONLY_VALID_GENERATORS_CAN_REQUEST_EXIT = "34";

    string public constant INVALID_ENCLAVE_KEY = "35";
    string public constant ONLY_GENERATOR_CAN_UNSTAKE_WITH_REQUEST = "36.a";
    string public constant ONLY_AFTER_DEADLINE = "37";
    string public constant INACTIVE_MARKET = "38";

    string public constant INSUFFICIENT_COMPUTE_TO_REDUCE = "39";

    string public constant ONLY_GENERATOR_CAN_DECREASE_COMPUTE_WITH_REQUEST = "40";

    string public constant REQUEST_ALREADY_IN_PLACE = "41";

    string public constant CAN_NOT_BE_LESS = "42";
    string public constant INVALID_CONTRACT_ADDRESS = "36.b";

    string public constant CANNOT_USE_MATCHING_ENGINE_ROLE = "43";
}
