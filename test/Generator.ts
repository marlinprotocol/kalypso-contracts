import { expect } from "chai";
import { ethers } from "hardhat";
import * as fs from "fs";
import { Provider, Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  Error,
  GeneratorRegistry,
  MockToken,
  PriorityLog,
  ProofMarketPlace,
  TransferVerifier__factory,
  EntityKeyRegistry,
  Transfer_verifier_wrapper__factory,
  IVerifier__factory,
  IVerifier,
} from "../typechain-types";

import {
  GeneratorData,
  MarketData,
  MockEnclave,
  MockGeneratorPCRS,
  generatorDataToBytes,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

describe("Checking Generator's multiple compute", () => {
  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let platformToken: MockToken;
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

  const ivsEnclave = new MockEnclave();
  const matchingEngineEnclave = new MockEnclave();

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

    await admin.sendTransaction({ to: ivsEnclave.getAddress(), value: "1000000000000000000" });
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
      ivsEnclave,
      matchingEngineEnclave,
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
    );

    proofMarketPlace = data.proofMarketPlace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    platformToken = data.platformToken;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;

    marketId = new BigNumber((await proofMarketPlace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketPlace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });

  it("Using Simple Transfer Verifier", async () => {
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
        proofMarketPlace,
        generatorRegistry,
        priorityLog,
        platformToken,
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
        proofMarketPlace,
        generatorRegistry,
        priorityLog,
        platformToken,
        errorLibrary,
        entityKeyRegistry,
      },
      askId,
      generator,
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
    await expect(proofMarketPlace.submitProof(askId, proofBytes))
      .to.emit(proofMarketPlace, "ProofCreated")
      .withArgs(askId, proofBytes);
  });

  it("Task Assignment fails if it exceeds compute capacity", async () => {
    const max_asks = generatorComputeAllocation.div(computeGivenToNewMarket).toFixed(0);

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
    // console.log({ inputBytes });

    for (let index = 0; index < parseInt(max_asks) + 2; index++) {
      const latestBlock = await ethers.provider.getBlockNumber();
      let assignmentExpiry = 100; // in blocks
      let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
      let maxTimeForProofGeneration = 10000; // in blocks

      if (index >= parseInt(max_asks)) {
        const ask = {
          marketId,
          proverData: inputBytes,
          reward: rewardForProofGeneration.toFixed(),
          expiry: assignmentExpiry + latestBlock,
          timeTakenForProofGeneration,
          deadline: latestBlock + maxTimeForProofGeneration,
          refundAddress: await prover.getAddress(),
        };

        await tokenToUse.connect(tokenHolder).transfer(await prover.getAddress(), ask.reward.toString());

        await tokenToUse.connect(prover).approve(await proofMarketPlace.getAddress(), ask.reward.toString());

        const proverBytes = ask.proverData;
        const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes(1)).toString()).multipliedBy(
          (proverBytes.length - 2) / 2,
        );

        await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
        await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());

        const askId = await proofMarketPlace.askCounter();

        await proofMarketPlace.connect(prover).createAsk(ask, marketId, "0x", "0x");

        const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);

        await expect(
          proofMarketPlace.connect(matchingEngine).assignTask(askId, await generator.getAddress(), "0x1234"),
        ).to.be.revertedWith(await errorLibrary.INSUFFICIENT_GENERATOR_COMPUTE_AVAILABLE());
      } else {
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
            proofMarketPlace,
            generatorRegistry,
            priorityLog,
            platformToken,
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
            proofMarketPlace,
            generatorRegistry,
            priorityLog,
            platformToken,
            errorLibrary,
            entityKeyRegistry,
          },
          askId,
          generator,
        );

        // console.log({ taskId, index });
      }
    }

    // let proofBytes = abiCoder.encode(
    //   ["uint256[8]"],
    //   [
    //     [
    //       transfer_verifier_proof.a[0],
    //       transfer_verifier_proof.a[1],
    //       transfer_verifier_proof.b[0][0],
    //       transfer_verifier_proof.b[0][1],
    //       transfer_verifier_proof.b[1][0],
    //       transfer_verifier_proof.b[1][1],
    //       transfer_verifier_proof.c[0],
    //       transfer_verifier_proof.c[1],
    //     ],
    //   ],
    // );
    // await expect(proofMarketPlace.submitProof(taskId, proofBytes))
    //   .to.emit(proofMarketPlace, "ProofCreated")
    //   .withArgs(askId, taskId, proofBytes);
  });

  it("Only registered generator should be able to add entity keys", async () => {
    const generatorEnclave = new MockEnclave(MockGeneratorPCRS);

    let types = ["address"];

    let values = [await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    let generatorAttestationBytes = generatorEnclave.getMockUnverifiedAttestation(await admin.getAddress());

    await expect(
      generatorRegistry.connect(generator).updateEncryptionKey(marketId, generatorAttestationBytes, signature),
    )
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await generator.getAddress(), marketId);
  });

  it("Only admin can set the generator registry role", async () => {
    const generatorRole = await entityKeyRegistry.KEY_REGISTER_ROLE();
    const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(false), admin.provider);
    await expect(entityKeyRegistry.connect(matchingEngine).addGeneratorRegistry(await proofMarketPlace.getAddress())).to
      .be.reverted;

    await entityKeyRegistry.addGeneratorRegistry(await proofMarketPlace.getAddress());
    expect(await entityKeyRegistry.hasRole(generatorRole, await proofMarketPlace.getAddress())).to.eq(true);
  });

  it("Updating with invalid key should revert", async () => {
    const generatorEnclave = new MockEnclave(MockGeneratorPCRS);

    let types = ["address"];
    let values = [await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    const invalidPubkey = "0x1234";

    let abiCoder = new ethers.AbiCoder();
    let validAttesationWithInvalidKey = abiCoder.encode(
      ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
      [
        "0x00",
        await admin.getAddress(),
        invalidPubkey,
        MockGeneratorPCRS[0],
        MockGeneratorPCRS[1],
        MockGeneratorPCRS[2],
        "0x00",
        "0x00",
      ],
    );

    await expect(
      generatorRegistry.connect(generator).updateEncryptionKey(marketId, validAttesationWithInvalidKey, signature),
    ).to.be.revertedWith(await errorLibrary.INVALID_ENCLAVE_KEY());
  });

  it("Remove key", async () => {
    // Adding key to registry
    const generatorEnclave = new MockEnclave(MockGeneratorPCRS);
    let types = ["address"];

    let values = [await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await generatorEnclave.signMessage(ethers.getBytes(digest));

    let newAttesationBytes = generatorEnclave.getMockUnverifiedAttestation(await admin.getAddress());

    await expect(generatorRegistry.connect(generator).updateEncryptionKey(marketId, newAttesationBytes, signature))
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await generator.getAddress(), marketId);

    // Checking key in registry
    const pub_key = await entityKeyRegistry.pub_key(generator.getAddress(), marketId);
    // console.log({ pub_key: pub_key });
    // console.log({pubBytes: pubBytes });
    expect(pub_key).to.eq(generatorEnclave.getUncompressedPubkey());

    // Removing key from registry
    await expect(generatorRegistry.connect(generator).removeEncryptionKey(marketId))
      .to.emit(entityKeyRegistry, "RemoveKey")
      .withArgs(await generator.getAddress(), marketId);
  });

  it("Generator Prechecks", async () => {
    const exponent = new BigNumber(10).pow(18).toFixed(0);

    const generatorData = await generatorRegistry.generatorRegistry(await generator.getAddress());
    expect(generatorComputeAllocation.toFixed(0)).to.eq(generatorData.declaredCompute.toString());
    expect(generatorData.computeConsumed).to.eq(0);
    expect(generatorData.totalStake).to.eq(generatorStakingAmount.toFixed(0));
    expect(generatorData.stakeLocked).to.eq(0);
    expect(generatorData.activeMarketPlaces).to.eq(1);
    expect(generatorData.intendedComputeUtilization).to.eq(exponent);
    expect(generatorData.intendedStakeUtilization).to.eq(exponent);

    const marketId = 0; // likely to be 0, if failed change it
    const generatorDataPerMarket = await generatorRegistry.generatorInfoPerMarket(
      await generator.getAddress(),
      marketId,
    );

    expect(generatorDataPerMarket.state).to.not.eq(0); // 0 means no generator
    expect(generatorDataPerMarket.computePerRequestRequired).to.eq(computeGivenToNewMarket.toFixed(0));
    expect(generatorDataPerMarket.proofGenerationCost).to.eq(minRewardByGenerator.toFixed(0));
    expect(generatorDataPerMarket.activeRequests).to.eq(0);
  });
});
