import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  EntityKeyRegistry,
  Error,
  GeneratorRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  PriorityLog,
  ProofMarketPlace,
  TransferVerifier__factory,
  Transfer_verifier_wrapper__factory,
} from "../typechain-types";

import {
  GeneratorData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockIVSPCRS,
  MockMEPCRS,
  generatorDataToBytes,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

describe("Proof Market Place for Transfer Verifier", () => {
  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let platformToken: MockToken;
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

  let iverifier: IVerifier;

  const ivsEnclave = new MockEnclave(MockIVSPCRS);
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
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
      godEnclave,
    );
    proofMarketPlace = data.proofMarketPlace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    platformToken = data.platformToken;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;

    await transferVerifierWrapper.setProofMarketPlaceContract(await proofMarketPlace.getAddress());

    marketId = new BigNumber((await proofMarketPlace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketPlace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });
  it("Check transfer verifier", async () => {
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
      admin.provider,
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
});
