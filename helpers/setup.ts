import { ethers, upgrades } from "hardhat";
import { Provider, Signer } from "ethers";

import {
  MockToken,
  ProofMarketplace,
  MockToken__factory,
  ProofMarketplace__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
  IVerifier,
  PriorityLog,
  PriorityLog__factory,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  EntityKeyRegistry,
} from "../typechain-types";
import BigNumber from "bignumber.js";

import { GodEnclavePCRS, MockEnclave } from ".";

interface SetupTemplate {
  mockToken: MockToken;
  generatorRegistry: GeneratorRegistry;
  proofMarketplace: ProofMarketplace;
  priorityLog: PriorityLog;
  errorLibrary: Error;
  entityKeyRegistry: EntityKeyRegistry;
}

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
  const mockToken = await new MockToken__factory(admin).deploy(
    await tokenHolder.getAddress(),
    totalTokenSupply.toFixed(),
    "Payment Token",
    "PT",
  );

  if (!godEnclave) {
    godEnclave = new MockEnclave(GodEnclavePCRS);
  }

  const AttestationVerifierContract = await ethers.getContractFactory("AttestationVerifier");
  const attestationVerifier = await upgrades.deployProxy(
    AttestationVerifierContract,
    [[godEnclave.pcrs], [godEnclave.getUncompressedPubkey()], await admin.getAddress()],
    {
      kind: "uups",
      constructorArgs: [],
    },
  );

  const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
  const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
    kind: "uups",
    constructorArgs: [await attestationVerifier.getAddress()],
  });
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

  const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
  const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
    kind: "uups",
    constructorArgs: [await mockToken.getAddress(), await entityKeyRegistry.getAddress()],
    initializer: false,
  });
  const generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), admin);

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

  await generatorRegistry.initialize(await admin.getAddress(), await proofMarketplace.getAddress());
  await proofMarketplace.initialize(await admin.getAddress());

  const register_role = await entityKeyRegistry.KEY_REGISTER_ROLE();

  await entityKeyRegistry.grantRole(register_role, await generatorRegistry.getAddress());
  await entityKeyRegistry.grantRole(register_role, await proofMarketplace.getAddress());

  await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

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

  await generatorRegistry
    .connect(generator)
    .register(await generator.getAddress(), totalComputeAllocation.toFixed(0), generatorStakingAmount.toFixed(0), generatorData);

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
