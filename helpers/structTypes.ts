// Struct.sol

enum BidState {
  Pending,
  Accepted,
  Rejected,
}

enum ProverState {
  Active,
  Inactive,
  Banned,
}

// Proof Marketplace
export interface Market {
  verifier: string; // address
  proverImageId: string; // bytes32
  slashingPenalty: string;
  activationBlock: string;
  ivsImageId: string; // bytes32
  creator: string; // address
  marketmetadata: string; // bytes
}

export interface Bid {
  marketId: string;
  reward: string;
  expiry: string;
  timeForProofGeneration: string;
  deadline: string;
  refundAddress: string; // address
  proverData: string; // bytes
}

export interface BidWithState {
  bid: Bid;
  state: BidState;
  requester: string; // address
  prover: string; // address
}

export interface TaskInfo {
  requester: string; // address
  prover: string; // address
  feePaid: string;
  deadline: string;
}

// Prover Registry
export interface Prover {
  rewardAddress: string; // address
  sumOfComputeAllocations: string;
  computeConsumed: string;
  activeMarketplaces: string;
  declaredCompute: string;
  intendedComputeUtilization: string;
  proverData: string; // bytes
}

export interface ProverInfoPerMarket {
  state: ProverState;
  computePerRequestRequired: string;
  proofGenerationCost: string;
  proposedTime: string;
  activeRequests: string;
}

// Staking Manager
export interface PoolConfig {
  share: string;
  enabled: boolean;
}

// Staking Pool
export interface PoolLockInfo {
  token: string; // address
  amount: string;
  transmitter: string; // address
}

// Native Staking
export interface NativeStakingLock {
  token: string; // address
  amount: string;
}

export interface TaskSlashed {
  bidId: string;
  prover: string; // address
  rewardAddress: string; // address
}

export interface WithdrawalRequest {
  stakeToken: string; // address
  amount: string;
  withdrawalTime: string;
}

// Symbiotic Staking
export interface VaultSnapshot {
  prover: string; // address
  vault: string; // address
  stakeToken: string; // address
  stakeAmount: string;
}

export interface SnapshotTxCountInfo {
  idxToSubmit: string;
  numOfTxs: string;
}

export interface CaptureTimestampInfo {
  blockNumber: string;
  transmitter: string; // address
}

export interface ConfirmedTimestamp {
  captureTimestamp: string;
  blockNumber: string;
  transmitter: string; // address
  transmitterComissionRate: string;
}

export interface SymbioticStakingLock {
  stakeToken: string; // address
  amount: string;
}

export interface EnclaveImage {
  PCR0: string; // bytes
  PCR1: string; // bytes
  PCR2: string; // bytes
}