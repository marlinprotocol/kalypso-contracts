import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";

import {
  MockToken,
  ProofMarketPlace,
  MockToken__factory,
  ProofMarketPlace__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
  IVerifier,
  IProofMarketPlace,
  PriorityLog,
  PriorityLog__factory,
} from "../typechain-types";
import BigNumber from "bignumber.js";

interface SetupTemplate {
  mockToken: MockToken;
  generatorRegistry: GeneratorRegistry;
  proofMarketPlace: ProofMarketPlace;
  priorityLog: PriorityLog;
}

export const createTask = async (
  matchingEngine: Signer,
  setupTemplate: SetupTemplate,
  askId: string,
  generator: Signer,
): Promise<string> => {
  const taskId = (await setupTemplate.proofMarketPlace.taskCounter()).toString();
  await setupTemplate.proofMarketPlace
    .connect(matchingEngine)
    .assignTask(askId.toString(), await generator.getAddress());

  return taskId;
};

export const createAsk = async (
  prover: Signer,
  tokenHolder: Signer,
  ask: IProofMarketPlace.AskStruct,
  setupTemplate: SetupTemplate,
): Promise<string> => {
  await setupTemplate.mockToken.connect(tokenHolder).transfer(await prover.getAddress(), ask.reward.toString());

  await setupTemplate.mockToken
    .connect(prover)
    .approve(await setupTemplate.proofMarketPlace.getAddress(), ask.reward.toString());

  const askId = await setupTemplate.proofMarketPlace.askCounter();
  await setupTemplate.proofMarketPlace.connect(prover).createAsk(ask);

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
  iverifier: IVerifier,
  generator: Signer,
  generatorData: string,
  matchingEngine: Signer,
  minRewardForGenerator: BigNumber,
): Promise<SetupTemplate> => {
  const mockToken = await new MockToken__factory(admin).deploy(
    await tokenHolder.getAddress(),
    totalTokenSupply.toFixed(),
  );

  const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
  const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
    kind: "uups",
    constructorArgs: [
      await mockToken.getAddress(),
      generatorStakingAmount.toFixed(),
      generatorSlashingPenalty.toFixed(),
    ],
    initializer: false,
  });
  const generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), admin);

  const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
  const proxy = await upgrades.deployProxy(
    ProofMarketPlace,
    [
      await admin.getAddress(),
      await mockToken.getAddress(),
      treasury,
      marketCreationCost.toFixed(),
      await generatorRegistry.getAddress(),
    ],
    { kind: "uups", constructorArgs: [] },
  );
  const proofMarketPlace = ProofMarketPlace__factory.connect(await proxy.getAddress(), admin);

  await generatorRegistry.initialize(await admin.getAddress(), await proofMarketPlace.getAddress());
  await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

  await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());
  await proofMarketPlace.connect(marketCreator).createMarketPlace(marketSetupBytes, await iverifier.getAddress());

  await mockToken.connect(tokenHolder).transfer(await generator.getAddress(), generatorStakingAmount.toFixed());

  await mockToken.connect(generator).approve(await generatorRegistry.getAddress(), generatorStakingAmount.toFixed());

  const marketId = ethers.keccak256(marketSetupBytes);

  await generatorRegistry.connect(generator).register(
    {
      rewardAddress: await generator.getAddress(),
      generatorData,
      amountLocked: 0,
      minReward: minRewardForGenerator.toFixed(),
    },
    marketId,
  );

  await proofMarketPlace
    .connect(admin)
    .grantRole(await proofMarketPlace.MATCHING_ENGINE_ROLE(), await matchingEngine.getAddress());

  const priorityLog = await new PriorityLog__factory(admin).deploy();
  return {
    mockToken,
    generatorRegistry,
    proofMarketPlace,
    priorityLog,
  };
};
