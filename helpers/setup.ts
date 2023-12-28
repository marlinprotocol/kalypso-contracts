import { ethers, upgrades } from "hardhat";
import { Provider, Signer } from "ethers";

import {
  MockToken,
  ProofMarketPlace,
  MockToken__factory,
  ProofMarketPlace__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
  IVerifier,
  PriorityLog,
  PriorityLog__factory,
  MockAttestationVerifier__factory,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  EntityKeyRegistry,
} from "../typechain-types";
import BigNumber from "bignumber.js";

interface SetupTemplate {
  mockToken: MockToken;
  generatorRegistry: GeneratorRegistry;
  proofMarketPlace: ProofMarketPlace;
  priorityLog: PriorityLog;
  platformToken: MockToken;
  errorLibrary: Error;
  entityKeyRegistry: EntityKeyRegistry;
}

export const createTask = async (
  matchingEnginePrivateKey: string,
  provider: Provider | null,
  setupTemplate: SetupTemplate,
  askId: string,
  generator: Signer,
) => {
  const matchingEngine: Signer = new ethers.Wallet(matchingEnginePrivateKey, provider);
  await setupTemplate.proofMarketPlace
    .connect(matchingEngine)
    .assignTask(askId.toString(), await generator.getAddress(), "0x");
};

export const createAsk = async (
  prover: Signer,
  tokenHolder: Signer,
  ask: ProofMarketPlace.AskStruct,
  setupTemplate: SetupTemplate,
  secretType: number,
): Promise<string> => {
  await setupTemplate.mockToken.connect(tokenHolder).transfer(await prover.getAddress(), ask.reward.toString());

  await setupTemplate.mockToken
    .connect(prover)
    .approve(await setupTemplate.proofMarketPlace.getAddress(), ask.reward.toString());

  const proverBytes = ask.proverData;
  const platformFee = new BigNumber(
    (await setupTemplate.proofMarketPlace.costPerInputBytes(secretType)).toString(),
  ).multipliedBy((proverBytes.length - 2) / 2);

  await setupTemplate.platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
  await setupTemplate.platformToken
    .connect(prover)
    .approve(await setupTemplate.proofMarketPlace.getAddress(), platformFee.toFixed());

  const askId = await setupTemplate.proofMarketPlace.askCounter();
  await setupTemplate.proofMarketPlace.connect(prover).createAsk(ask, secretType, "0x", "0x");

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
  ivsUrl: string,
  iverifier: IVerifier,
  generator: Signer,
  generatorData: string,
  ivsEciesPubKey: string,
  matchingEnginePubkey: string,
  minRewardForGenerator: BigNumber,
  totalComputeAllocation: BigNumber,
  computeToNewMarket: BigNumber,
  isEnclaveRequired: boolean = true,
): Promise<SetupTemplate> => {
  const mockToken = await new MockToken__factory(admin).deploy(
    await tokenHolder.getAddress(),
    totalTokenSupply.toFixed(),
  );

  const platformToken = await new MockToken__factory(admin).deploy(
    await tokenHolder.getAddress(),
    totalTokenSupply.toFixed(),
  );

  const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
  const entityKeyRegistry = await new EntityKeyRegistry__factory(admin).deploy(
    await mockAttestationVerifier.getAddress(),
    await admin.getAddress(),
  );

  const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
  const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
    kind: "uups",
    constructorArgs: [await mockToken.getAddress(), await entityKeyRegistry.getAddress()],
    initializer: false,
  });
  const generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), admin);

  const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
  const proxy = await upgrades.deployProxy(ProofMarketPlace, [await admin.getAddress()], {
    kind: "uups",
    constructorArgs: [
      await mockToken.getAddress(),
      await platformToken.getAddress(),
      marketCreationCost.toFixed(),
      treasury,
      await generatorRegistry.getAddress(),
      await entityKeyRegistry.getAddress(),
      await mockAttestationVerifier.getAddress(),
    ],
  });
  const proofMarketPlace = ProofMarketPlace__factory.connect(await proxy.getAddress(), admin);

  await generatorRegistry.initialize(await admin.getAddress(), await proofMarketPlace.getAddress());

  const register_role = await entityKeyRegistry.KEY_REGISTER_ROLE();

  await entityKeyRegistry.grantRole(register_role, await generatorRegistry.getAddress());
  await entityKeyRegistry.grantRole(register_role, await proofMarketPlace.getAddress());

  await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

  await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());

  let abiCoder = new ethers.AbiCoder();

  let matchingEngineAttestationBytes = abiCoder.encode(
    ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
    ["0x00", await admin.getAddress(), matchingEnginePubkey, "0x00", "0x00", "0x00", "0x00", "0x00"],
  );

  await proofMarketPlace.updateMatchingEngineEncryptionKeyAndSigner(matchingEngineAttestationBytes);

  let ivsAttestationBytes = abiCoder.encode(
    ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
    ["0x00", await admin.getAddress(), ivsEciesPubKey, "0x00", "0x00", "0x00", "0x00", "0x00"],
  );

  await proofMarketPlace
    .connect(marketCreator)
    .createMarketPlace(
      marketSetupBytes,
      await iverifier.getAddress(),
      generatorSlashingPenalty.toFixed(0),
      isEnclaveRequired,
      ivsAttestationBytes,
      Buffer.from(ivsUrl, "ascii"),
    );

  await mockToken.connect(tokenHolder).transfer(await generator.getAddress(), generatorStakingAmount.toFixed());

  await mockToken.connect(generator).approve(await generatorRegistry.getAddress(), generatorStakingAmount.toFixed());

  // const marketId = ethers.keccak256(marketSetupBytes);
  const marketId = new BigNumber((await proofMarketPlace.marketCounter()).toString()).minus(1).toFixed();

  await generatorRegistry
    .connect(generator)
    .register(await generator.getAddress(), totalComputeAllocation.toFixed(0), generatorData);
  await generatorRegistry.connect(generator).stake(await generator.getAddress(), generatorStakingAmount.toFixed(0));
  await generatorRegistry
    .connect(generator)
    .joinMarketPlace(marketId, computeToNewMarket.toFixed(0), minRewardForGenerator.toFixed(), 100);

  const priorityLog = await new PriorityLog__factory(admin).deploy();

  const errorLibrary = await new Error__factory(admin).deploy();
  return {
    mockToken,
    generatorRegistry,
    proofMarketPlace,
    priorityLog,
    platformToken,
    errorLibrary,
    entityKeyRegistry,
  };
};
