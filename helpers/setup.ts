import BigNumber from 'bignumber.js';
import {
  BigNumberish,
  Provider,
  Signer,
} from 'ethers';
import {
  ethers,
  upgrades,
} from 'hardhat';

import {
  AttestationVerifier,
  AttestationVerifier__factory,
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  IVerifier,
  MockToken,
  MockToken__factory,
  NativeStaking,
  NativeStaking__factory,
  POND,
  POND__factory,
  PriorityLog,
  PriorityLog__factory,
  ProofMarketplace,
  ProofMarketplace__factory,
  ProverManager,
  ProverManager__factory,
  StakingManager,
  StakingManager__factory,
  SymbioticStaking,
  SymbioticStaking__factory,
  SymbioticStakingReward,
  SymbioticStakingReward__factory,
  USDC,
  USDC__factory,
  WETH,
  WETH__factory,
} from '../typechain-types';
import {
  BridgeEnclavePCRS,
  GodEnclavePCRS,
  MockEnclave,
} from './';
import { Bid } from './structTypes';

interface SetupTemplate {
  mockToken: MockToken;
  proverManager: ProverManager;
  proofMarketplace: ProofMarketplace;
  priorityLog: PriorityLog;
  errorLibrary: Error;
  entityKeyRegistry: EntityKeyRegistry;
  attestationVerifier: AttestationVerifier;

  /* Staking Contracts */
  stakingManager: StakingManager;
  nativeStaking: NativeStaking;
  symbioticStaking: SymbioticStaking;
  symbioticStakingReward: SymbioticStakingReward;
}

export const stakingContractConfig = {
  WITHDRAWAL_DURATION: new BigNumber(60 * 60 * 2), // 2 hours
};

export const exponent = new BigNumber(10).pow(18);

export const createTask = async (
  matchingEngineEnclave: MockEnclave,
  provider: Provider | null,
  setupTemplate: SetupTemplate,
  askId: string,
  prover: Signer,
) => {
  const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), provider);
  await setupTemplate.proofMarketplace.connect(matchingEngine).assignTask(askId.toString(), await prover.getAddress(), "0x");
};

export const createBid = async (
  prover: Signer,
  tokenHolder: Signer,
  bid: Bid,
  setupTemplate: SetupTemplate,
  secretType: number,
): Promise<string> => {
  await setupTemplate.mockToken.connect(tokenHolder).transfer(await prover.getAddress(), bid.reward.toString());

  await setupTemplate.mockToken.connect(prover).approve(await setupTemplate.proofMarketplace.getAddress(), bid.reward.toString());

  const bidId = await setupTemplate.proofMarketplace.bidCounter();
  await setupTemplate.proofMarketplace.connect(prover).createBid(bid, secretType, "0x", "0x", "0x");

  return bidId.toString();
};

export const rawSetup = async (
  admin: Signer,
  tokenHolder: Signer,
  totalTokenSupply: BigNumber,
  proverStakingAmount: BigNumber,
  proverSlashingPenalty: BigNumber,
  treasury: string,
  marketCreationCost: BigNumber,
  marketCreator: Signer,
  marketSetupBytes: string,
  _ivsUrl: string,
  iverifier: IVerifier,
  prover: Signer,
  proverData: string,
  ivsEnclave: MockEnclave,
  matchingEngineEnclave: MockEnclave,
  proverEnclave: MockEnclave,
  minRewardForProver: BigNumber,
  totalComputeAllocation: BigNumber,
  computeToNewMarket: BigNumber,
  godEnclave?: MockEnclave,
  bridgeEnclave?: MockEnclave,
): Promise<SetupTemplate> => {
  //-------------------------------- Contract Deployment --------------------------------//

  // PaymentToken
  const mockToken = await new MockToken__factory(admin).deploy(
    await tokenHolder.getAddress(),
    totalTokenSupply.toFixed(),
    "Payment Token",
    "PT",
  );

  if (!godEnclave) {
    godEnclave = new MockEnclave(GodEnclavePCRS);
  }

  // AttestationVerifier
  const AttestationVerifierContract = await ethers.getContractFactory("AttestationVerifier");
  const attestationVerifierProxy = await upgrades.deployProxy(
    AttestationVerifierContract,
    [[godEnclave.pcrs], [godEnclave.getUncompressedPubkey()], await admin.getAddress()],
    {
      kind: "uups",
      constructorArgs: [],
    },
  );
  const attestationVerifier = AttestationVerifier__factory.connect(await attestationVerifierProxy.getAddress(), admin);
  if (bridgeEnclave) {
    await attestationVerifier.whitelistEnclaveImage(bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);
    await attestationVerifier.whitelistEnclaveKey(bridgeEnclave.getUncompressedPubkey(), bridgeEnclave.getImageId());
  }

  // EntityKeyRegistry
  const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
  const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
    kind: "uups",
    constructorArgs: [await attestationVerifier.getAddress()],
  });
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

  // StakingManager
  const StakingManagerContract = await ethers.getContractFactory("StakingManager");
  const stakingManagerProxy = await upgrades.deployProxy(StakingManagerContract, [], {
    kind: "uups",
    constructorArgs: [],
    initializer: false,
  });
  const stakingManager = StakingManager__factory.connect(await stakingManagerProxy.getAddress(), admin);

  // ProverManager
  const ProverManagerContract = await ethers.getContractFactory("ProverManager");
  const proverManagerProxy = await upgrades.deployProxy(ProverManagerContract, [], {
    kind: "uups",
    initializer: false,
  });
  const proverManager = ProverManager__factory.connect(await proverManagerProxy.getAddress(), admin);

  // ProofMarketplace
  const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
  const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
    kind: "uups",
    initializer: false,
  });
  const proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), admin);

  // NativeStaking
  const NativeStakingContract = await ethers.getContractFactory("NativeStaking");
  const nativeStakingProxy = await upgrades.deployProxy(NativeStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const nativeStaking = NativeStaking__factory.connect(await nativeStakingProxy.getAddress(), admin);

  // SmybioticStaking
  const SymbioticStakingContract = await ethers.getContractFactory("SymbioticStaking");
  const symbioticStakingProxy = await upgrades.deployProxy(SymbioticStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const symbioticStaking = SymbioticStaking__factory.connect(await symbioticStakingProxy.getAddress(), admin);

  // SymbioticStakingReward
  const SymbioticStakingRewardContract = await ethers.getContractFactory("SymbioticStakingReward");
  const symbioticStakingRewardProxy = await upgrades.deployProxy(SymbioticStakingRewardContract, [], {
    kind: "uups",
    constructorArgs: [],
    initializer: false,
  });
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(await symbioticStakingRewardProxy.getAddress(), admin);

  //-------------------------------- Contract Init --------------------------------//

  // Initialize ProverManager
  await proverManager.initialize(
    await admin.getAddress(),
    await proofMarketplace.getAddress(),
    await stakingManager.getAddress(),
    await entityKeyRegistry.getAddress(),
  );

  // Initialize ProofMarketplace
  await proofMarketplace.initialize(
    await admin.getAddress(),
    await mockToken.getAddress(),
    treasury,
    await proverManager.getAddress(),
    await entityKeyRegistry.getAddress(),
    marketCreationCost.toFixed(),
  );

  // Initialize StakingManager
  await stakingManager.initialize(
    await admin.getAddress(),
    await proofMarketplace.getAddress(),
    await symbioticStaking.getAddress(),
    await mockToken.getAddress(),
  );

  // Initialize NativeStaking
  await nativeStaking.initialize(
    await admin.getAddress(),
    await stakingManager.getAddress(),
    stakingContractConfig.WITHDRAWAL_DURATION.toFixed(), // 2 hours
    await mockToken.getAddress(),
  );

  // Initialize SymbioticStaking
  await symbioticStaking.initialize(
    await admin.getAddress(),
    await attestationVerifier.getAddress(),
    await proofMarketplace.getAddress(),
    await stakingManager.getAddress(),
    await symbioticStakingReward.getAddress(),
    await mockToken.getAddress(),
  );

  // Initialize SymbioticStakingReward
  await symbioticStakingReward.initialize(
    await admin.getAddress(), // address _admin
    await proofMarketplace.getAddress(), // address _jobManager
    await symbioticStaking.getAddress(), // address _symbioticStaking
    await mockToken.getAddress(), // address _feeRewardToken
  );

  await proofMarketplace.grantRole(await proofMarketplace.SYMBIOTIC_STAKING_ROLE(), await symbioticStaking.getAddress());

  // `StakingManager.PROVER_MANAGER_ROLE` -> `ProverManager`
  await stakingManager.grantRole(await stakingManager.PROVER_MANAGER_ROLE(), await proverManager.getAddress());
  // `SymbioticStaking.STAKING_MANAGER_ROLE` -> `StakingManager`
  await symbioticStaking.grantRole(await symbioticStaking.STAKING_MANAGER_ROLE(), await stakingManager.getAddress());
  // `SymbioticStaking.BRIDGE_ENCLAVE_UPDATES_ROLE` -> admin
  await symbioticStaking.grantRole(await symbioticStaking.BRIDGE_ENCLAVE_UPDATES_ROLE(), await admin.getAddress());
  // `SymbioticStakingReward.SYMBIOTIC_STAKING_ROLE` -> `SymbioticStaking`
  await symbioticStakingReward.grantRole(await symbioticStakingReward.SYMBIOTIC_STAKING_ROLE(), await symbioticStaking.getAddress());
  // `NativeStaking.STAKING_MANAGER_ROLE` -> `StakingManager`
  await nativeStaking.grantRole(await nativeStaking.STAKING_MANAGER_ROLE(), await stakingManager.getAddress());
  // `EntityKeyRegistry.KEY_REGISTER_ROLE` -> `ProverManager`
  await entityKeyRegistry.grantRole(await entityKeyRegistry.KEY_REGISTER_ROLE(), await proverManager.getAddress());
  // `EntityKeyRegistry.KEY_REGISTER_ROLE` -> `ProofMarketplace`
  await entityKeyRegistry.grantRole(await entityKeyRegistry.KEY_REGISTER_ROLE(), await proofMarketplace.getAddress());

  // Transfer marketCreationCost to ProofMarketplace
  await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());
  // Approve marketCreationCost for ProofMarketplace
  await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

  let matchingEngineAttestationBytes = await matchingEngineEnclave.getVerifiedAttestation(godEnclave);

  let types = ["bytes", "address"];
  let values = [matchingEngineAttestationBytes, await proofMarketplace.getAddress()];

  let abicode = new ethers.AbiCoder();
  let encoded = abicode.encode(types, values);
  let digest = ethers.keccak256(encoded);
  let signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

  await proofMarketplace.grantRole(await proofMarketplace.UPDATER_ROLE(), await admin.getAddress());
  await proofMarketplace.setMatchingEngineImage(matchingEngineEnclave.getPcrRlp());
  await proofMarketplace.verifyMatchingEngine(matchingEngineAttestationBytes, signature);

  await proofMarketplace
    .connect(marketCreator)
    .createMarket(
      marketSetupBytes,
      await iverifier.getAddress(),
      proverEnclave.getPcrRlp(),
      ivsEnclave.getPcrRlp(),
    );

  await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), proverStakingAmount.toFixed());

  await mockToken.connect(prover).approve(await proverManager.getAddress(), proverStakingAmount.toFixed());

  const marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

  await proverManager
    .connect(prover)
    .register(await prover.getAddress(), totalComputeAllocation.toFixed(0), /*  proverStakingAmount.toFixed(0),  */ proverData);

  {
    let proverAttestationBytes = await proverEnclave.getVerifiedAttestation(godEnclave);

    let types = ["bytes", "address"];

    let values = [proverAttestationBytes, await prover.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await proverEnclave.signMessage(ethers.getBytes(digest));

    await proverManager
      .connect(prover)
      .joinMarketplace(
        marketId,
        computeToNewMarket.toFixed(0),
        minRewardForProver.toFixed(),
        100,
        new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
        true,
        proverAttestationBytes,
        signature,
      );
  }

  const priorityLog = await new PriorityLog__factory(admin).deploy();

  const errorLibrary = await new Error__factory(admin).deploy();
  return {
    mockToken,
    proverManager,
    proofMarketplace,
    priorityLog,
    errorLibrary,
    entityKeyRegistry,
    attestationVerifier,
    /* Staking Contracts */
    stakingManager,
    nativeStaking,
    symbioticStaking,
    symbioticStakingReward,
  };
};

interface StakingTokens {
  pond: POND;
  weth: WETH;
}

export const stakingSetup = async (
  admin: Signer,
  stakingManager: StakingManager,
  nativeStaking: NativeStaking,
  symbioticStaking: SymbioticStaking,
  symbioticStakingReward: SymbioticStakingReward,
): Promise<StakingTokens> => {

  /*-------------------------------- Constants  --------------------------------*/
  const percent = (amount: BigNumber.Value) => {
    const exponent = new BigNumber(10).pow(18);
    return BigNumber(amount).multipliedBy(exponent).dividedBy(100).toFixed(0);
  };

  const TWENTY_PERCENT = percent(20);
  const SIXTY_PERCENT = percent(60);
  const FORTY_PERCENT = percent(40);
  const HUNDRED_PERCENT = percent(100);

  /*-------------------------------- StakingTokens Deployment --------------------------------*/

  const pond = await new POND__factory(admin).deploy(await admin.getAddress());
  const weth = await new WETH__factory(admin).deploy(await admin.getAddress());
  const usdc = await new USDC__factory(admin).deploy(await admin.getAddress());

  /*-------------------------------- StakingManager Config --------------------------------*/

  // Add StakingPools
  await stakingManager.connect(admin).addStakingPool(await symbioticStaking.getAddress());
  await stakingManager.connect(admin).addStakingPool(await nativeStaking.getAddress());

  // NativeStaking 0%, SymbioticStaking 100%
  const nativeStakingShare = new BigNumber(10).pow(18).multipliedBy(0); // 0 %
  const symbioticStakingShare = new BigNumber(10).pow(18).multipliedBy(1); // 100%
  await stakingManager.connect(admin).setPoolRewardShare(
    [await nativeStaking.getAddress(), await symbioticStaking.getAddress()],
    [nativeStakingShare.toFixed(0), symbioticStakingShare.toFixed(0)],
  );

  // Enable pools
  await stakingManager.connect(admin).setEnabledPool(
    await nativeStaking.getAddress(),
    true
  )
  await stakingManager.connect(admin).setEnabledPool(
    await symbioticStaking.getAddress(),
    true
  )

  /*-------------------------------- NativeStaking Config --------------------------------*/

  // Add POND to NativeStaking
  await nativeStaking.connect(admin).addStakeToken(
    await pond.getAddress(),
    HUNDRED_PERCENT, // 100% weight for selection
  );
  // Amount to lock
  await nativeStaking.connect(admin).setStakeAmountToLock(
    await pond.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(2).toFixed(0), // 2 POND locked per job creation
  );

  /*-------------------------------- SymbioticStaking Config --------------------------------*/
  
  // Stake Tokens and weights
  await symbioticStaking.connect(admin).addStakeToken(
    await pond.getAddress(),
    SIXTY_PERCENT, // 60% weight for selection
  );
  await symbioticStaking.connect(admin).addStakeToken(
    await weth.getAddress(),
    FORTY_PERCENT, // 40% weight for selection
  );

  // Set base transmitter comission rate and submission cooldown
  await symbioticStaking.connect(admin).setBaseTransmitterComissionRate(TWENTY_PERCENT);
  await symbioticStaking.connect(admin).setSubmissionCooldown(60 * 60 * 12); // 12 hours

  // amount to lock
  await symbioticStaking.connect(admin).setAmountToLock(
    await pond.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(2).toFixed(0), // 2 POND locked per job creation
  );
  await symbioticStaking.connect(admin).setAmountToLock(
    await weth.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(3).toFixed(0), // 3 WETH locked per job creation
  );

  /*-------------------------------- SymbioticStakingReward Config --------------------------------*/
  
  return {
    pond,
    weth,
  };
};

export const proverSelfStake = async (
  nativeStaking: NativeStaking,
  admin: Signer,
  prover: Signer,
  stakeToken: POND,
  amount: BigNumber
) => {
  await stakeToken.connect(admin).transfer(await prover.getAddress(), amount.toFixed(0));
  await stakeToken.connect(prover).approve(await nativeStaking.getAddress(), amount.toFixed(0));

  await nativeStaking.connect(prover).stake(
    await stakeToken.getAddress(),
    await prover.getAddress(),
    amount.toFixed(0)
  );
}

export interface VaultSnapshot {
  prover: string;
  vault: string;
  stakeToken: string;
  stakeAmount: BigNumberish;
}

export interface TaskSlashed {
  bidId: number;
  prover: string;
  rewardAddress: string;
}

export const toEthSignedMessageHash = (messageHash: string): string => {
  const prefix = "\x19Ethereum Signed Message:\n32";
  const prefixBytes = ethers.toUtf8Bytes(prefix);
  const messageHashBytes = ethers.toBeArray(messageHash);
  const combined = ethers.concat([prefixBytes, messageHashBytes]);
  return ethers.keccak256(combined);
}

export interface SubmitVaultSnapshotParams {
  index: number;
  numOfTxs: number;
  captureTimestamp: BigNumberish;
  imageId: string;
  snapshotData: VaultSnapshot[],
}

export const submitVaultSnapshot = async (
  symbioticStaking: SymbioticStaking,
  bridgeEnclave: MockEnclave,
  transmitter: Signer,
  params: SubmitVaultSnapshotParams
) => {
  const abiCoder = new ethers.AbiCoder();
  
  const vaultSnapshotData = encodeSnapshotData(params.snapshotData);
  const STAKE_SNAPSHOT_TYPE = await symbioticStaking.STAKE_SNAPSHOT_TYPE();
  const dataToSign = abiCoder.encode(
    ["bytes32", "uint256", "uint256", "uint256", "bytes"], // _type, _index, _numOfTxs, _captureTimestamp, _data
    [STAKE_SNAPSHOT_TYPE, params.index, params.numOfTxs, params.captureTimestamp, vaultSnapshotData]
  );

  const messageHash = toEthSignedMessageHash(ethers.keccak256(dataToSign));
  const signature = await bridgeEnclave.signMessageWithoutPrefix(messageHash);
  const attestation = await bridgeEnclave.getMockAttestation();
  const proof = abiCoder.encode(
    ["bytes", "bytes"],
    [signature, attestation]
  );

  await symbioticStaking.connect(transmitter).submitVaultSnapshot(
    params.index,
    params.numOfTxs,
    params.captureTimestamp,
    params.imageId,
    vaultSnapshotData,
    proof
  );
};

export interface SubmitSlashResultParams {
  index: number;
  numOfTxs: number;
  captureTimestamp: BigNumberish;
  lastBlockNumber: BigNumberish;
  imageId: string;
  slashResultData: TaskSlashed[],
}

export const submitSlashResult = async (
  symbioticStaking: SymbioticStaking,
  bridgeEnclave: MockEnclave,
  transmitter: Signer,
  params: SubmitSlashResultParams
) => {
  const abiCoder = new ethers.AbiCoder();

  const slashResultData = encodeSlashResultData(params.slashResultData);
  const SLASH_RESULT_TYPE = await symbioticStaking.SLASH_RESULT_TYPE();
  const dataToSign = abiCoder.encode(
    ["bytes32", "uint256", "uint256", "uint256", "bytes"], // _type, _index, _numOfTxs, _captureTimestamp, _data
    [SLASH_RESULT_TYPE, params.index, params.numOfTxs, params.captureTimestamp, slashResultData]
  );
  const messageHash = toEthSignedMessageHash(ethers.keccak256(dataToSign));
  const signature = await bridgeEnclave.signMessageWithoutPrefix(messageHash);
  const attestation = await bridgeEnclave.getMockAttestation();
  const proof = abiCoder.encode(
    ["bytes", "bytes"],
    [signature, attestation]
  );

  await symbioticStaking.connect(transmitter).submitSlashResult(
    params.index,
    params.numOfTxs,
    params.captureTimestamp,
    params.lastBlockNumber,
    params.imageId,
    slashResultData,
    proof
  );
}

const encodeSnapshotData = (vaultSnapshots: VaultSnapshot[]) => {
  const abiCoder = new ethers.AbiCoder();
  return abiCoder.encode(
    ["tuple(address, address, address, uint256)[]"],
    [vaultSnapshots.map(snapshot => [
      snapshot.prover,
      snapshot.vault,
      snapshot.stakeToken,
      snapshot.stakeAmount
    ])]
  );
};

const encodeSlashResultData = (taskSlashed: TaskSlashed[]) => {
  const abiCoder = new ethers.AbiCoder();
  return abiCoder.encode(
    ["tuple(uint256, address, address)[]"],
    [taskSlashed.map(slash => [
      slash.bidId,
      slash.prover,
      slash.rewardAddress
    ])]
  );
};


