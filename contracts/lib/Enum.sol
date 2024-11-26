// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Enum {
    /* ProofMarketplace */
    enum BidState {
        NULL,
        CREATE,
        UNASSIGNED,
        ASSIGNED,
        COMPLETE,
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

    /* Symbiotic Staking */
    enum SubmissionStatus {
        NONE,
        STAKE_SNAPSHOT_DONE,
        COMPLETE
    }

    /* Priority Log */
    enum Priority {
        NONE,
        COST,
        TIME,
        DEADLINE
    }
}

