import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  ProverRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  ProofMarketplace,
  XorVerifier__factory,
  Xor2_verifier_wrapper__factory,
  PriorityLog,
  Error,
  EntityKeyRegistry,
  NativeStaking,
  StakingManager,
  SymbioticStaking,
  SymbioticStakingReward,
} from "../typechain-types";

import {
  ProverData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockProverPCRS,
  MockIVSPCRS,
  MockMEPCRS,
  proverDataToBytes,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

import * as circom_verifier_inputs from "../helpers/sample/circomVerifier/input.json";
import * as circom_verifier_proof from "../helpers/sample/circomVerifier/proof.json";

describe("Proof Market Place for Circom Verifier", () => {
  let proofMarketplace: ProofMarketplace;
  let proverRegistry: ProverRegistry;
  let tokenToUse: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;
  let stakingManager: StakingManager;
  let nativeStaking: NativeStaking;
  let symbioticStaking: SymbioticStaking;
  let symbioticStakingReward: SymbioticStakingReward;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let proverData: ProverData;

  let iverifier: IVerifier;

  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const proverEnclave = new MockEnclave(MockProverPCRS);
  const godEnclave = new MockEnclave(GodEnclavePCRS);

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

    marketSetupData = {
      zkAppName: "circom addition",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "this should be nclave url",
    };

    proverData = {
      name: "some custom name for the generator",
    };

    const circomVerifier = await new XorVerifier__factory(admin).deploy();
    let abiCoder = new ethers.AbiCoder();
    let inputBytes = abiCoder.encode(["uint[1]"], [[circom_verifier_inputs[0]]]);
    let proofBytes = abiCoder.encode(
      ["uint[2]", "uint[2][2]", "uint[2]"],
      [circom_verifier_proof[0], circom_verifier_proof[1], circom_verifier_proof[2]],
    );

    const circomVerifierWrapper = await new Xor2_verifier_wrapper__factory(admin).deploy(
      await circomVerifier.getAddress(),
      inputBytes,
      proofBytes,
    );

    iverifier = IVerifier__factory.connect(await circomVerifierWrapper.getAddress(), admin);

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
      proverDataToBytes(proverData),
      ivsEnclave,
      matchingEngineEnclave,
      proverEnclave,
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
      godEnclave,
    );
    proofMarketplace = data.proofMarketplace;
    proverRegistry = data.proverRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;
    stakingManager = data.stakingManager;
    nativeStaking = data.nativeStaking;
    symbioticStaking = data.symbioticStaking;
    symbioticStakingReward = data.symbioticStakingReward;

    await circomVerifierWrapper.setProofMarketplaceContract(await proofMarketplace.getAddress());

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });
  it("Check circom verifier", async () => {
    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(["uint[1]"], [[circom_verifier_inputs[0]]]);
    // console.log({ inputBytes });
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

    const bidId = await setup.createBid(
      prover,
      tokenHolder,
      {
        marketId,
        proverData: inputBytes,
        reward: rewardForProofGeneration.toFixed(),
        expiry: assignmentExpiry + latestBlock.toString(),
        timeTakenForProofGeneration: timeTakenForProofGeneration.toString(),
        deadline: (latestBlock + maxTimeForProofGeneration).toString(),
        refundAddress: await prover.getAddress(),
      },
      {
        mockToken: tokenToUse,
        proofMarketplace,
        proverRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
        stakingManager,
        nativeStaking,
        symbioticStaking,
        symbioticStakingReward,
      },
      1,
    );

    await setup.createTask(
      matchingEngineEnclave,
      admin.provider,
      {
        mockToken: tokenToUse,
        proofMarketplace,
        proverRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
        stakingManager,
        nativeStaking,
        symbioticStaking,
        symbioticStakingReward,
      },
      bidId,
      generator,
    );

    let proofBytes = abiCoder.encode(
      ["uint[2]", "uint[2][2]", "uint[2]"],
      [circom_verifier_proof[0], circom_verifier_proof[1], circom_verifier_proof[2]],
    );
    await expect(proofMarketplace.submitProof(bidId, proofBytes)).to.emit(proofMarketplace, "ProofCreated").withArgs(bidId, proofBytes);
  });
});
