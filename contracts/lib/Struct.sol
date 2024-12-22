// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Enum} from "./Enum.sol";

library Struct {

    /*=========================== Proof Marketplace =============================*/
    struct Market {
        address verifier; // verifier address for the market place
        bytes32 proverImageId; // use bytes32(0) for public market
        uint256 slashingPenalty;
        uint256 activationBlock;
        bytes32 ivsImageId;
        address creator;
        bytes marketmetadata;
    }
    struct Bid {
        uint256 marketId;
        uint256 reward;
        // the block number by which the bid should be assigned by matching engine
        uint256 expiry;
        uint256 timeTakenForProofGeneration;
        uint256 deadline;
        address refundAddress;
        bytes proverData;
    }

    struct BidWithState {
        Bid bid;
        Enum.BidState state;
        address requester;
        address prover;
    }

    struct TaskInfo {
        address requester;
        address prover;
        uint256 feePaid;
        uint256 deadline;
    }

    /*========================= Prover Registry =========================*/
    struct Prover {
        address rewardAddress;
        uint256 sumOfComputeAllocations;
        uint256 computeConsumed;
        uint256 activeMarketplaces;
        uint256 declaredCompute;
        uint256 intendedComputeUtilization;
        bytes proverData;
    }

    struct ProverInfoPerMarket {
        Enum.ProverState state;
        uint256 computePerRequestRequired;
        uint256 proofGenerationCost;
        uint256 proposedTime;
        uint256 activeRequests;
    }

    /*========================= Staking Manager ===========================*/

    struct PoolConfig {
        uint256 share;
        bool enabled;
    }

    /*=========================== Staking Pool ============================*/

    struct PoolLockInfo {
        address token;
        uint256 amount;
        address transmitter;
    }

    /*========================== Native Staking ===========================*/

    struct NativeStakingLock {
        address token;
        uint256 amount;
    }

    struct TaskSlashed {
        uint256 bidId;
        address prover;
        address rewardAddress;
    }

    struct WithdrawalRequest {
        address stakeToken;
        uint256 amount;
        uint256 withdrawalTime;
    }

    /*========================= Symbiotic Staking =========================*/

    struct VaultSnapshot {
        address prover;
        address vault;
        address stakeToken;
        uint256 stakeAmount;
    }

    struct SnapshotTxCountInfo {
        uint256 idxToSubmit; // idx of pratial snapshot tx to submit
        uint256 numOfTxs; // total number of txs for the snapshot
    }

    struct CaptureTimestampInfo {
        uint256 blockNumber; // L1 Block Number for parsing slash result
        address transmitter;
    }

    struct ConfirmedTimestamp {
        uint256 captureTimestamp;
        uint256 blockNumber; // L1 Block Number for parsing slash result
        address transmitter;
        uint256 transmitterComissionRate;
    }

    struct SymbioticStakingLock {
        address stakeToken;
        uint256 amount;
    }

    struct EnclaveImage {
        bytes PCR0;
        bytes PCR1;
        bytes PCR2;
    }
}