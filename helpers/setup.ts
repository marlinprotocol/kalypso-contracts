import BigNumber from 'bignumber.js';
import {
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
  NativeStaking__factory,
  PriorityLog,
  PriorityLog__factory,
  ProofMarketplace,
  ProofMarketplace__factory,
  StakingManager__factory,
  SymbioticStaking__factory,
  SymbioticStakingReward__factory,
} from '../typechain-types';
import {
  GodEnclavePCRS,
  MockEnclave,
} from './';

interface SetupTemplate {
  mockToken: MockToken;
  generatorRegistry: GeneratorRegistry;
  proofMarketplace: ProofMarketplace;
  priorityLog: PriorityLog;
  errorLibrary: Error;
  entityKeyRegistry: EntityKeyRegistry;
}

export const stakingContractConfig = {
  WITHDRAWAL_DURATION: new BigNumber(60 * 60 * 2), // 2 hours
};

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
    constructorArgs: [],
    initializer: false,
  });
  const nativeStaking = NativeStaking__factory.connect(await nativeStakingProxy.getAddress(), admin);

  // SmybioticStaking
  const SymbioticStakingContract = await ethers.getContractFactory("SymbioticStaking");
  const symbioticStakingProxy = await upgrades.deployProxy(SymbioticStakingContract, [], {
    kind: "uups",
    constructorArgs: [],
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
  };
};
