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
} from "../typechain-types";

import { setup } from "../helpers";

import * as circom_verifier_inputs from "../helpers/sample/circomVerifier/input.json";
import * as circom_verifier_proof from "../helpers/sample/circomVerifier/proof.json";

describe.skip("Proof Market Place for Circom Verifier", () => {
  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;
  let matchingEngine: Signer;

  let marketCreator: Signer;
  let marketSetupBytes: string;
  let marketId: string;

  let generatorData: string;

  let iverifier: IVerifier;

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(18).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    treasury = signers[2];
    marketCreator = signers[3];
    prover = signers[4];
    generator = signers[5];
    matchingEngine = signers[6];

    marketSetupBytes = "0x1234";
    generatorData = "0x1234";

    marketId = ethers.keccak256(marketSetupBytes);

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
      marketSetupBytes,
      iverifier,
      generator,
      generatorData,
      matchingEngine,
    );
    proofMarketPlace = data.proofMarketPlace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
  });
  it("Check circom verifier", async () => {
    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(["uint[1]"], [[circom_verifier_inputs]]);
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 1000; // in blocks
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
      },
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry },
    );

    const taskId = await setup.createTask(
      matchingEngine,
      { mockToken: tokenToUse, proofMarketPlace, generatorRegistry },
      askId,
      generator,
    );

    let proofBytes = abiCoder.encode(["uint[2]", "uint[2][2]", "uint[2]"], [[circom_verifier_proof]]);
    await expect(proofMarketPlace.submitProof(taskId, proofBytes))
      .to.emit(proofMarketPlace, "ProofCreated")
      .withArgs(taskId);
  });
});
