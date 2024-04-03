import { expect } from "chai";
import { ethers } from "hardhat";
import { Provider, Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  Error,
  GeneratorRegistry,
  MockToken,
  PriorityLog,
  ProofMarketplace,
  TransferVerifier__factory,
  EntityKeyRegistry,
  Transfer_verifier_wrapper__factory,
  IVerifier__factory,
  IVerifier,
} from "../typechain-types";

import {
  GeneratorData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockGeneratorPCRS,
  MockMEPCRS,
  generatorDataToBytes,
  generatorFamilyId,
  ivsFamilyId,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

describe("Checking Case where generator and ivs image is same", () => {
  let proofMarketplace: ProofMarketplace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;
  let iverifier: IVerifier;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let generatorData: GeneratorData;

  const ivsAndGeneratorEnclaveCombined = new MockEnclave(MockGeneratorPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);

  const godEnclave = new MockEnclave(GodEnclavePCRS);

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const generatorComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);

  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByGenerator = new BigNumber(10).pow(18).multipliedBy(199);

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    treasury = signers[2];
    marketCreator = signers[3];
    prover = signers[4];
    generator = signers[5];

    marketSetupData = {
      zkAppName: "transfer verifier",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "this should be nclave url",
    };

    generatorData = {
      name: "some custom name for the generator",
    };

    await admin.sendTransaction({ to: ivsAndGeneratorEnclaveCombined.getAddress(), value: "1000000000000000000" });
    await admin.sendTransaction({ to: matchingEngineEnclave.getAddress(), value: "1000000000000000000" });

    const transferVerifier = await new TransferVerifier__factory(admin).deploy();

    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(
      ["uint256[5]"],
      [
        [
          transfer_verifier_inputs[0],
          transfer_verifier_inputs[1],
          transfer_verifier_inputs[2],
          transfer_verifier_inputs[3],
          transfer_verifier_inputs[4],
        ],
      ],
    );

    let proofBytes = abiCoder.encode(
      ["uint256[8]"],
      [
        [
          transfer_verifier_proof.a[0],
          transfer_verifier_proof.a[1],
          transfer_verifier_proof.b[0][0],
          transfer_verifier_proof.b[0][1],
          transfer_verifier_proof.b[1][0],
          transfer_verifier_proof.b[1][1],
          transfer_verifier_proof.c[0],
          transfer_verifier_proof.c[1],
        ],
      ],
    );
    const transferVerifierWrapper = await new Transfer_verifier_wrapper__factory(admin).deploy(
      await transferVerifier.getAddress(),
      inputBytes,
      proofBytes,
    );

    iverifier = IVerifier__factory.connect(await transferVerifierWrapper.getAddress(), admin);

    let treasuryAddress = await treasury.getAddress();

    let data = await setup.rawSetup(
      admin,
      tokenHolder,
      totalTokenSupply,
      generatorStakingAmount,
      generatorSlashingPenalty,
      treasuryAddress,
      marketCreationCost,
      marketCreator,
      marketDataToBytes(marketSetupData),
      marketSetupData.inputOuputVerifierUrl,
      iverifier,
      generator,
      generatorDataToBytes(generatorData),
      ivsAndGeneratorEnclaveCombined, // USED AS IVS HERE
      matchingEngineEnclave,
      ivsAndGeneratorEnclaveCombined, // USED AS GENERATOR HERE
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
      godEnclave,
    );

    proofMarketplace = data.proofMarketplace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });

  it("Add new images for generators and ivs", async () => {
    const newGeneratorImages = [MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs()].map(
      (a) => new MockEnclave(a),
    );

    const newIvsImages = [MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs()].map(
      (a) => new MockEnclave(a),
    );

    await proofMarketplace.connect(marketCreator).addExtraImages(
      marketId,
      newGeneratorImages.map((a) => a.getPcrRlp()),
      newIvsImages.map((a) => a.getPcrRlp()),
    );

    for (let index = 0; index < newGeneratorImages.length; index++) {
      const generator = newGeneratorImages[index];
      const isAllowed = await entityKeyRegistry.isImageInFamily(generator.getImageId(), generatorFamilyId(marketId));
      expect(isAllowed).is.true;
    }

    for (let index = 0; index < newIvsImages.length; index++) {
      const ivs = newIvsImages[index];
      const isAllowed = await entityKeyRegistry.isImageInFamily(ivs.getImageId(), ivsFamilyId(marketId));
      expect(isAllowed).is.true;
    }
  });

  it("Submit proof for invalid requests directly from generator", async () => {
    let abiCoder = new ethers.AbiCoder();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks
    const latestBlock = await ethers.provider.getBlockNumber();

    let inputBytes = abiCoder.encode(
      ["uint256[5]"],
      [
        [
          transfer_verifier_inputs[0],
          transfer_verifier_inputs[1],
          transfer_verifier_inputs[2],
          transfer_verifier_inputs[3],
          transfer_verifier_inputs[4],
        ],
      ],
    );

    const askId = await setup.createAsk(
      prover,
      tokenHolder,
      {
        marketId,
        proverData: inputBytes,
        reward: rewardForProofGeneration.toFixed(),
        expiry: assignmentExpiry + latestBlock,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      },
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      1,
    );

    await setup.createTask(
      matchingEngineEnclave,
      admin.provider as Provider,
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      askId,
      generator,
    );

    const askData = await proofMarketplace.listOfAsk(askId);
    const types = ["uint256", "bytes"];

    const values = [askId, askData.ask.proverData];

    const abicode = new ethers.AbiCoder();
    const encoded = abicode.encode(types, values);
    const digest = ethers.keccak256(encoded);
    const signature = await ivsAndGeneratorEnclaveCombined.signMessage(ethers.getBytes(digest));

    await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

    await expect(proofMarketplace.submitProofForInvalidInputs(askId, signature)).to.emit(proofMarketplace, "InvalidInputsDetected");
  });

  it("Submit proof for invalid requests directly from new generators added by market maker", async () => {
    let abiCoder = new ethers.AbiCoder();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks
    const latestBlock = await ethers.provider.getBlockNumber();

    let inputBytes = abiCoder.encode(
      ["uint256[5]"],
      [
        [
          transfer_verifier_inputs[0],
          transfer_verifier_inputs[1],
          transfer_verifier_inputs[2],
          transfer_verifier_inputs[3],
          transfer_verifier_inputs[4],
        ],
      ],
    );

    const askId = await setup.createAsk(
      prover,
      tokenHolder,
      {
        marketId,
        proverData: inputBytes,
        reward: rewardForProofGeneration.toFixed(),
        expiry: assignmentExpiry + latestBlock,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      },
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      1,
    );

    await setup.createTask(
      matchingEngineEnclave,
      admin.provider as Provider,
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      askId,
      generator,
    );

    const updateIvsKey = async (ivsEnclave: MockEnclave) => {
      // use any enclave here as AV is mocked
      let ivsAttestationBytes = await ivsEnclave.getVerifiedAttestation(godEnclave); // means ivs should get verified attestation from noUseEnclave

      let types = ["bytes", "address"];
      let values = [ivsAttestationBytes, await generator.getAddress()];

      let abicode = new ethers.AbiCoder();
      let encoded = abicode.encode(types, values);
      let digest = ethers.keccak256(encoded);
      let signature = await ivsEnclave.signMessage(ethers.getBytes(digest));

      // use any enclave to get verfied attestation as mockAttesationVerifier is used here
      await expect(generatorRegistry.connect(generator).addIvsKey(marketId, ivsAttestationBytes, signature))
        .to.emit(generatorRegistry, "AddIvsKey")
        .withArgs(marketId, ivsEnclave.getAddress());
    };

    const newGeneratorImage = new MockEnclave(MockEnclave.someRandomPcrs());
    await proofMarketplace
      .connect(marketCreator)
      .addExtraImages(marketId, [newGeneratorImage.getPcrRlp()], [newGeneratorImage.getPcrRlp()]);

    await updateIvsKey(newGeneratorImage);

    const askData = await proofMarketplace.listOfAsk(askId);
    const types = ["uint256", "bytes"];

    const values = [askId, askData.ask.proverData];

    const abicode = new ethers.AbiCoder();
    const encoded = abicode.encode(types, values);
    const digest = ethers.keccak256(encoded);
    const signature = await newGeneratorImage.signMessage(ethers.getBytes(digest));

    await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

    await expect(proofMarketplace.submitProofForInvalidInputs(askId, signature)).to.emit(proofMarketplace, "InvalidInputsDetected");
  });
});
