// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Enum {
    /* ProofMarketplace */
    enum BidState {
        NULL,
        CREATED,
        UNASSIGNED,
        ASSIGNED,
        COMPLETED,
        DEADLINE_CROSSED
    }

    enum SecretType {
        NULL,
        CALLDATA,
        EXTERNAL
    }

    /* ProverRegistry */
    enum ProverState {
        NULL,
        JOINED,
        NO_COMPUTE_AVAILABLE,
        WIP,
        REQUESTED_FOR_EXIT
    }


    /* Priority Log */
    enum Priority {
        NONE,
        COST,
        TIME,
        DEADLINE
    }
}

