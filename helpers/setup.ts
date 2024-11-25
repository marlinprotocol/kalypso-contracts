import BigNumber from 'bignumber.js';
import {
  BigNumberish,
  BytesLike,
  Provider,
  Signer,
} from 'ethers';
import {
  ethers,
  upgrades,
} from 'hardhat';

import {
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
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
  GodEnclavePCRS,
  MockEnclave,
} from './';
import { expect } from "chai";

interface SetupTemplate {
  mockToken: MockToken;
  generatorRegistry: GeneratorRegistry;
  proofMarketplace: ProofMarketplace;
  priorityLog: PriorityLog;
  errorLibrary: Error;
  entityKeyRegistry: EntityKeyRegistry;

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
  generator: Signer,
) => {
  const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), provider);
  await setupTemplate.proofMarketplace.connect(matchingEngine).assignTask(askId.toString(), await generator.getAddress(), "0x");
};

export const createAsk = async (
  prover: Signer,
  tokenHolder: Signer,
  ask: ProofMarketplace.AskStruct,
  setupTemplate: SetupTemplate,
  secretType: number,
): Promise<string> => {
  await setupTemplate.mockToken.connect(tokenHolder).transfer(await prover.getAddress(), ask.reward.toString());

  await setupTemplate.mockToken.connect(prover).approve(await setupTemplate.proofMarketplace.getAddress(), ask.reward.toString());

  const askId = await setupTemplate.proofMarketplace.askCounter();
  await setupTemplate.proofMarketplace.connect(prover).createAsk(ask, secretType, "0x", "0x");

  return askId.toString();
};

export const rawSetup = async (
  admin: Signer,
  tokenHolder: Signer,
  totalTokenSupply: BigNumber,
  generatorStakingAmount: BigNumber,
  generatorSlashingPenalty: BigNumber,
  treasury: string,
  marketCreationCost: BigNumber,
  marketCreator: Signer,
  marketSetupBytes: string,
  _ivsUrl: string,
  iverifier: IVerifier,
  generator: Signer,
  generatorData: string,
  ivsEnclave: MockEnclave,
  matchingEngineEnclave: MockEnclave,
  generatorEnclave: MockEnclave,
  minRewardForGenerator: BigNumber,
  totalComputeAllocation: BigNumber,
  computeToNewMarket: BigNumber,
  godEnclave?: MockEnclave,
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
  const attestationVerifier = await upgrades.deployProxy(
    AttestationVerifierContract,
    [[godEnclave.pcrs], [godEnclave.getUncompressedPubkey()], await admin.getAddress()],
    {
      kind: "uups",
      constructorArgs: [],
    },
  );

  // EntityKeyRegistry
  const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
  const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
    kind: "uups",
    constructorArgs: [await attestationVerifier.getAddress()],
  });
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

  // GeneratorRegistry
  const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
  const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
    kind: "uups",
    constructorArgs: [await mockToken.getAddress(), await entityKeyRegistry.getAddress()],
    initializer: false,
  });
  const generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), admin);

  // ProofMarketplace
  const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
  const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
    kind: "uups",
    constructorArgs: [
      await mockToken.getAddress(),
      marketCreationCost.toFixed(),
      treasury,
      await generatorRegistry.getAddress(),
      await entityKeyRegistry.getAddress(),
    ],
    initializer: false,
  });
  const proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), admin);

  // StakingManager
  const StakingManagerContract = await ethers.getContractFactory("StakingManager");
  const stakingManagerProxy = await upgrades.deployProxy(StakingManagerContract, [], {
    kind: "uups",
    constructorArgs: [],
    initializer: false,
  });
  const stakingManager = StakingManager__factory.connect(await stakingManagerProxy.getAddress(), admin);

  // NativeStaking
  const NativeStakingContract = await ethers.getContractFactory("NativeStaking");
  const nativeStakingProxy = await upgrades.deployProxy(NativeStakingContract, [], {
    kind: "uups",
    constructorArgs: [await generatorRegistry.getAddress()],
    initializer: false,
  });
  const nativeStaking = NativeStaking__factory.connect(await nativeStakingProxy.getAddress(), admin);

  // SmybioticStaking
  const SymbioticStakingContract = await ethers.getContractFactory("SymbioticStaking");
  const symbioticStakingProxy = await upgrades.deployProxy(SymbioticStakingContract, [], {
    kind: "uups",
    constructorArgs: [await generatorRegistry.getAddress()],
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

  // Initialize GeneratorRegistry
  await generatorRegistry.initialize(await admin.getAddress(), await proofMarketplace.getAddress(), await stakingManager.getAddress()); // TODO

  // Initialize ProofMarketplace
  await proofMarketplace.initialize(await admin.getAddress());

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
    stakingContractConfig.WITHDRAWAL_DURATION.toFixed(),
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

  // Grant `GENERATOR_REGISTRY_ROLE` to StakingManager
  await stakingManager.grantRole(await stakingManager.GENERATOR_REGISTRY_ROLE(), await generatorRegistry.getAddress());

  // Grant `KEY_REGISTER_ROLE` to GeneratorRegistry, ProofMarketplace
  const register_role = await entityKeyRegistry.KEY_REGISTER_ROLE();
  await entityKeyRegistry.grantRole(register_role, await generatorRegistry.getAddress());
  await entityKeyRegistry.grantRole(register_role, await proofMarketplace.getAddress());

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
    .createMarketplace(
      marketSetupBytes,
      await iverifier.getAddress(),
      generatorSlashingPenalty.toFixed(0),
      generatorEnclave.getPcrRlp(),
      ivsEnclave.getPcrRlp(),
    );

  await mockToken.connect(tokenHolder).transfer(await generator.getAddress(), generatorStakingAmount.toFixed());

  await mockToken.connect(generator).approve(await generatorRegistry.getAddress(), generatorStakingAmount.toFixed());

  const marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

  // await generatorRegistry
  //   .connect(generator)
  //   .register(await generator.getAddress(), totalComputeAllocation.toFixed(0), generatorStakingAmount.toFixed(0), generatorData);
  await generatorRegistry
    .connect(generator)
    .register(await generator.getAddress(), totalComputeAllocation.toFixed(0), /*  generatorStakingAmount.toFixed(0),  */ generatorData);

  {
    let generatorAttestationBytes = await generatorEnclave.getVerifiedAttestation(godEnclave);

    let types = ["bytes", "address"];

    let values = [generatorAttestationBytes, await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    await generatorRegistry
      .connect(generator)
      .joinMarketplace(
        marketId,
        computeToNewMarket.toFixed(0),
        minRewardForGenerator.toFixed(),
        100,
        true,
        generatorAttestationBytes,
        signature,
      );
  }

  const priorityLog = await new PriorityLog__factory(admin).deploy();

  const errorLibrary = await new Error__factory(admin).deploy();
  return {
    mockToken,
    generatorRegistry,
    proofMarketplace,
    priorityLog,
    errorLibrary,
    entityKeyRegistry,
    /* Staking Contracts */
    stakingManager,
    nativeStaking,
    symbioticStaking,
    symbioticStakingReward,
  };
};

interface StakingTokens {
  POND: POND;
  WETH: WETH;
  USDC: USDC;
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

  const POND = await new POND__factory(admin).deploy(await admin.getAddress());
  const WETH = await new WETH__factory(admin).deploy(await admin.getAddress());
  const USDC = await new USDC__factory(admin).deploy(await admin.getAddress());

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
    await POND.getAddress(),
    HUNDRED_PERCENT, // 100% weight for selection
  );
  // Amount to lock
  await nativeStaking.connect(admin).setAmountToLock(
    await POND.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(2).toFixed(0), // 2 POND locked per job creation
  );

  /*-------------------------------- SymbioticStaking Config --------------------------------*/
  
  // Stake Tokens and weights
  await symbioticStaking.connect(admin).addStakeToken(
    await POND.getAddress(),
    SIXTY_PERCENT, // 60% weight for selection
  );
  await symbioticStaking.connect(admin).addStakeToken(
    await WETH.getAddress(),
    FORTY_PERCENT, // 40% weight for selection
  );

  // Set base transmitter comission rate and submission cooldown
  await symbioticStaking.connect(admin).setBaseTransmitterComissionRate(TWENTY_PERCENT);
  await symbioticStaking.connect(admin).setSubmissionCooldown(60 * 60 * 12); // 12 hours

  // amount to lock
  await symbioticStaking.connect(admin).setAmountToLock(
    await POND.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(2).toFixed(0), // 2 POND locked per job creation
  );
  await symbioticStaking.connect(admin).setAmountToLock(
    await WETH.getAddress(),
    new BigNumber(10).pow(18).multipliedBy(0.2).toFixed(0), // 0.2 WETH locked per job creation
  );

  /*-------------------------------- SymbioticStakingReward Config --------------------------------*/
  
  return {
    POND,
    WETH,
    USDC,
  };
};

export const generatorSelfStake = async (
  nativeStaking: NativeStaking,
  admin: Signer,
  generator: Signer,
  stakeToken: POND,
  amount: BigNumber
) => {
  await stakeToken.connect(admin).transfer(await generator.getAddress(), amount.toFixed(0));
  await stakeToken.connect(generator).approve(await nativeStaking.getAddress(), amount.toFixed(0));

  await nativeStaking.connect(generator).stake(
    await stakeToken.getAddress(),
    await generator.getAddress(),
    amount.toFixed(0)
  );
}

export interface VaultSnapshotData {
  operator: string;
  vault: string;
  stakeToken: string;
  stakeAmount: BigNumberish;
}

export const submistVaultSnapshot = async(
  transmitter: Signer,
  symbioticStaking: SymbioticStaking,
  snapshotData: VaultSnapshotData[],
) => {
  const timestamp = new BigNumber((await ethers.provider.getBlock('latest'))?.timestamp ?? 0).toFixed(0);

  // submit snapshot
  await symbioticStaking.connect(transmitter).submitVaultSnapshot(
    0,
    1,
    timestamp,
    new ethers.AbiCoder().encode(
      [
        "tuple(address operator, address vault, address stakeToken, uint256 stakeAmount)[]"
      ],
      [snapshotData]
    ),
    "0x"
  );

  await symbioticStaking.connect(transmitter).submitSlashResult(
    0,
    1,
    timestamp,
    "0x",
    "0x"
  );
}
