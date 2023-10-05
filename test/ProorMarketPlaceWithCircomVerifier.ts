import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  GeneratorRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  ProofMarketPlace,
  XorVerifier__factory,
  Xor2_verifier_wrapper__factory,
  PriorityLog,
  Error,
} from "../typechain-types";

import { GeneratorData, MarketData, generatorDataToBytes, marketDataToBytes, setup } from "../helpers";

import * as circom_verifier_inputs from "../helpers/sample/circomVerifier/input.json";
import * as circom_verifier_proof from "../helpers/sample/circomVerifier/proof.json";

describe("Proof Market Place for Circom Verifier", () => {
  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let platformToken: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;
  let matchingEngine: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let generatorData: GeneratorData;

  let iverifier: IVerifier;

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByGenerator = new BigNumber(10).pow(18).multipliedBy(199);
  const generatorComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);

  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    treasury = signers[2];
    marketCreator = signers[3];
    prover = signers[4];
    generator = signers[5];
    matchingEngine = signers[6];

    marketSetupData = {
      zkAppName: "circom addition",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "this should be nclave url",
    };

    generatorData = {
      name: "some custom name for the generator",
    };

    marketId = ethers.keccak256(marketDataToBytes(marketSetupData));

    const circomVerifier = await new XorVerifier__factory(admin).deploy();
    const circomVerifierWrapper = await new Xor2_verifier_wrapper__factory(admin).deploy(
      await circomVerifier.getAddress(),
    );

    iverifier = IVerifier__factory.connect(await circomVerifierWrapper.getAddress(), admin);

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
      iverifier,
      generator,
      generatorDataToBytes(generatorData),
      matchingEngine,
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
    );
    proofMarketPlace = data.proofMarketPlace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    platformToken = data.platformToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
  });
  it("Check circom verifier", async () => {
    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(["uint[1]"], [[circom_verifier_inputs[0]]]);
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
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry, priorityLog, platformToken, errorLibrary },
    );

    const taskId = await setup.createTask(
      matchingEngine,
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry, priorityLog, platformToken, errorLibrary },
      askId,
      generator,
    );

    let proofBytes = abiCoder.encode(
      ["uint[2]", "uint[2][2]", "uint[2]"],
      [circom_verifier_proof[0], circom_verifier_proof[1], circom_verifier_proof[2]],
    );
    await expect(proofMarketPlace.submitProof(taskId, proofBytes))
      .to.emit(proofMarketPlace, "ProofCreated")
      .withArgs(askId, taskId, proofBytes);
  });
});
