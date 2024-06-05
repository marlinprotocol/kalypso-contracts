import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  AttestationVerifier,
  AttestationVerifier__factory,
  EntityKeyRegistry,
  Error,
  GeneratorRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  PriorityLog,
  ProofMarketplace,
  Tee_verifier_wrapper,
  Tee_verifier_wrapper__factory,
  Tee_verifier_wrapper_factory__factory,
} from "../typechain-types";

import {
  GeneratorData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockGeneratorPCRS,
  MockIVSPCRS,
  MockMEPCRS,
  generatorDataToBytes,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

describe("Proof Market Place for Tee Verifier", () => {
  let proofMarketplace: ProofMarketplace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;

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

  let attestationVerifier: AttestationVerifier;
  let tee_verifier_wrapper: Tee_verifier_wrapper;
  let iverifier: IVerifier;

  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const generatorEnclave = new MockEnclave(MockGeneratorPCRS);
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
      zkAppName: "tee verifier",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "this should be nclave url",
    };

    generatorData = {
      name: "some custom name for the generator",
    };

    const AttestationVerifierContract = await ethers.getContractFactory("AttestationVerifier");
    const _attestationVerifier = await upgrades.deployProxy(
      AttestationVerifierContract,
      [[godEnclave.pcrs], [godEnclave.getUncompressedPubkey()], await admin.getAddress()],
      {
        kind: "uups",
        constructorArgs: [],
      },
    );
    attestationVerifier = AttestationVerifier__factory.connect(await _attestationVerifier.getAddress(), admin);

    tee_verifier_wrapper = await new Tee_verifier_wrapper__factory(admin).deploy(
      await admin.getAddress(),
      await attestationVerifier.getAddress(),
      [generatorEnclave.getPcrRlp()],
    );

    let tee_verifier_key_attestation = await generatorEnclave.getVerifiedAttestation(godEnclave);
    await tee_verifier_wrapper.verifyKey(tee_verifier_key_attestation);

    iverifier = IVerifier__factory.connect(await tee_verifier_wrapper.getAddress(), admin);

    let treasuryAddress = await treasury.getAddress();
    await treasury.sendTransaction({ to: matchingEngineEnclave.getAddress(), value: "1000000000000000000" });

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
      ivsEnclave,
      matchingEngineEnclave,
      generatorEnclave,
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

  it("Check tee verifier deployer", async () => {
    const tee_verifier_deployer = await new Tee_verifier_wrapper_factory__factory(admin).deploy();

    // create new tee verifier by code
    const tx = tee_verifier_deployer.create_tee_verifier_wrapper(await admin.getAddress(), await attestationVerifier.getAddress(), [
      ivsEnclave.getPcrRlp(),
    ]);
    await expect(tx).to.emit(tee_verifier_deployer, "TeeVerifierWrapperCreated");
  });

  it("Check tee verifier", async () => {
    let inputBytes = "0x1234";
    let proofBytes = "0x0987";
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

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
      admin.provider,
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

    let abiCoder = new ethers.AbiCoder();
    const messageBytes = abiCoder.encode(["bytes", "bytes"], [inputBytes, proofBytes]);
    let digest = ethers.keccak256(messageBytes);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    let proofToSend = abiCoder.encode(["bytes", "bytes", "bytes"], [inputBytes, proofBytes, signature]);

    await expect(proofMarketplace.submitProof(askId, proofToSend)).to.emit(proofMarketplace, "ProofCreated").withArgs(askId, proofToSend);
  });

  it("Shoulf fail: if inputs don't match when used to generate proof", async () => {
    let inputBytes = "0x1234";
    let proofBytes = "0x0987";
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

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
      admin.provider,
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

    let abiCoder = new ethers.AbiCoder();

    let wrongInputs = "0x8888";

    const messageBytes = abiCoder.encode(["bytes", "bytes"], [wrongInputs, proofBytes]);
    let digest = ethers.keccak256(messageBytes);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    let proofToSend = abiCoder.encode(["bytes", "bytes", "bytes"], [wrongInputs, proofBytes, signature]);

    await expect(proofMarketplace.submitProof(askId, proofToSend)).to.be.revertedWithCustomError(proofMarketplace, "InvalidInputs");
  });

  it("Shoulf fail: if wrong signature is provided", async () => {
    let inputBytes = "0x1234";
    let proofBytes = "0x0987";
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

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
      admin.provider,
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

    let abiCoder = new ethers.AbiCoder();

    let wrongInputs = "0x8888";

    const messageBytes = abiCoder.encode(["bytes", "bytes"], [wrongInputs, proofBytes]);
    let digest = ethers.keccak256(messageBytes);
    let wrongSignature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    let proofToSend = abiCoder.encode(["bytes", "bytes", "bytes"], [inputBytes, proofBytes, wrongSignature]);

    await expect(proofMarketplace.submitProof(askId, proofToSend)).to.be.revertedWithCustomError(
      tee_verifier_wrapper,
      "AttestationAutherKeyNotVerified",
    );
  });

  it("Shoulf fail: proofs generated from some random enclave should fail", async () => {
    let inputBytes = "0x1234";
    let proofBytes = "0x0987";
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

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
      admin.provider,
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

    let abiCoder = new ethers.AbiCoder();

    const messageBytes = abiCoder.encode(["bytes", "bytes"], [inputBytes, proofBytes]);
    let digest = ethers.keccak256(messageBytes);

    const randomEnclave = new MockEnclave(MockEnclave.someRandomPcrs());
    let signature = await randomEnclave.signMessage(ethers.getBytes(digest));

    let proofToSend = abiCoder.encode(["bytes", "bytes", "bytes"], [inputBytes, proofBytes, signature]);

    await expect(proofMarketplace.submitProof(askId, proofToSend)).to.be.revertedWithCustomError(
      tee_verifier_wrapper,
      "AttestationAutherKeyNotVerified",
    );
  });
});
