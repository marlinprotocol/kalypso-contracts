// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

library Error {
    // Administrative and Miscellaneous Errors
    string public constant ONLY_ADMIN_CAN_CALL = "A1";
    string public constant CANNOT_BE_ADMIN_LESS = "A2";
    string public constant CANNOT_BE_ZERO = "A3";
    string public constant CAN_N0T_BE_SLASHED = "A4";
    string public constant INSUFFICIENT_STAKE_TO_LOCK = "A5";
    string public constant ENCLAVE_KEY_NOT_VERIFIED = "A6";
    string public constant EXCEEDS_ACCEPTABLE_RANGE = "A7";
    string public constant INVALID_CONTRACT_ADDRESS = "A8";
    string public constant CANNOT_USE_MATCHING_ENGINE_ROLE = "A9";
    string public constant INVALID_ENCLAVE_SIGNATURE = "A10";

    // Generator-related Errors
    string public constant GENERATOR_ALREADY_EXISTS = "G1";
    string public constant INVALID_GENERATOR = "G2";
    string public constant CAN_NOT_LEAVE_WITH_ACTIVE_MARKET = "G3";
    string public constant ASSIGN_ONLY_TO_IDLE_GENERATORS = "G4";
    string public constant INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE = "G5";
    string public constant ONLY_WORKING_GENERATORS = "G6";
    string public constant INVALID_ENCLAVE_KEY = "G7";
    string public constant ONLY_VALID_GENERATORS_CAN_REQUEST_EXIT = "G8";
    string public constant INVALID_GENERATOR_STATE_PER_MARKET = "G9";
    string public constant UNSTAKE_REQUEST_NOT_IN_PLACE = "G10";
    string public constant REDUCE_COMPUTE_REQUEST_NOT_IN_PLACE = "G11";
    string public constant MAX_PARALLEL_REQUESTS_PER_MARKET_EXCEEDED = "G12";
    string public constant KEY_ALREADY_EXISTS = "G13";

    // Market-related Errors
    string public constant INVALID_MARKET = "M1";
    string public constant ALREADY_JOINED_MARKET = "M2";
    string public constant CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE = "M3";
    string public constant CAN_NOT_LEAVE_MARKET_WITH_ACTIVE_REQUEST = "M4";
    string public constant MARKET_ALREADY_EXISTS = "M5";
    string public constant INACTIVE_MARKET = "M6";

    // Task and Request Errors
    string public constant CAN_NOT_ASSIGN_EXPIRED_TASKS = "TR1";
    string public constant INVALID_INPUTS = "TR2";
    string public constant ARITY_MISMATCH = "TR3";
    string public constant ONLY_MATCHING_ENGINE_CAN_ASSIGN = "TR4";
    string public constant REQUEST_ALREADY_IN_PLACE = "TR5";

    // Proof and State Errors
    string public constant SHOULD_BE_IN_CREATE_STATE = "PS1";
    string public constant PROOF_PRICE_MISMATCH = "PS2";
    string public constant PROOF_TIME_MISMATCH = "PS3";
    string public constant ONLY_EXPIRED_ASKS_CAN_BE_CANCELLED = "PS4";
    string public constant ONLY_ASSIGNED_ASKS_CAN_BE_PROVED = "PS5";
    string public constant INVALID_PROOF = "PS6";
    string public constant SHOULD_BE_IN_CROSSED_DEADLINE_STATE = "PS7";
    string public constant SHOULD_BE_IN_ASSIGNED_STATE = "PS8";
    string public constant ONLY_GENERATOR_CAN_DISCARD_REQUEST = "PS9";
}
