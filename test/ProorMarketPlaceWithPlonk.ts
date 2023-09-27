import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  GeneratorRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  PriorityLog,
  ProofMarketPlace,
  UltraVerifier__factory,
  Plonk_verifier_wrapper__factory,
} from "../typechain-types";

import { GeneratorData, MarketData, generatorDataToBytes, marketDataToBytes, setup } from "../helpers";
import * as fs from "fs";

import { a as plonkInputs } from "../helpers/sample/plonk/verification_params.json";
const plonkProof = "0x" + fs.readFileSync("helpers/sample/plonk/p.proof", "utf-8");

describe("Proof Market Place for Plonk Verifier", () => {
  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let platformToken: MockToken;
  let priorityLog: PriorityLog;

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
      zkAppName: "plonk verifier",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
    };

    generatorData = {
      name: "some custom name for the generator",
    };

    marketId = ethers.keccak256(marketDataToBytes(marketSetupData));

    const plonkVerifier = await new UltraVerifier__factory(admin).deploy();
    const plonkVerifierWrapper = await new Plonk_verifier_wrapper__factory(admin).deploy(
      await plonkVerifier.getAddress(),
    );

    iverifier = IVerifier__factory.connect(await plonkVerifierWrapper.getAddress(), admin);

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
    );
    proofMarketPlace = data.proofMarketPlace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    platformToken = data.platformToken;
    priorityLog = data.priorityLog;
  });
  it("Check plonk verifier", async () => {
    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(["bytes32[]"], [[plonkInputs]]);
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
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry, priorityLog, platformToken },
    );

    const taskId = await setup.createTask(
      matchingEngine,
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry, priorityLog, platformToken },
      askId,
      generator,
    );

    // console.log({ plonkProof });
    let proofBytes = abiCoder.encode(["bytes"], [plonkProof]);
    await expect(proofMarketPlace.submitProof(taskId, proofBytes))
      .to.emit(proofMarketPlace, "ProofCreated")
      .withArgs(askId, taskId, proofBytes);
  });
});
