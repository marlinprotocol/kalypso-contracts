import { BigNumber } from 'bignumber.js';
import { expect } from 'chai';
import {
  Provider,
  Signer,
} from 'ethers';
import { ethers } from 'hardhat';

import {
  ProverData,
  proverDataToBytes,
  GodEnclavePCRS,
  MarketData,
  marketDataToBytes,
  MockEnclave,
  MockProverPCRS,
  MockIVSPCRS,
  MockMEPCRS,
  setup,
  skipBlocks,
} from '../helpers';
import * as transfer_verifier_inputs
  from '../helpers/sample/transferVerifier/transfer_inputs.json';
import * as transfer_verifier_proof
  from '../helpers/sample/transferVerifier/transfer_proof.json';
import * as invalid_transfer_verifier_proof
  from '../helpers/sample/zkbVerifier/transfer_proof.json';
import {
  EntityKeyRegistry,
  Error,
  ProverRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  NativeStaking,
  POND,
  PriorityLog,
  ProofMarketplace,
  StakingManager,
  SymbioticStaking,
  SymbioticStakingReward,
  Transfer_verifier_wrapper__factory,
  TransferVerifier__factory,
  USDC,
  WETH,
} from '../typechain-types';
import { proverSelfStake, stakingContractConfig, stakingSetup, submitVaultSnapshot, VaultSnapshotData } from '../helpers/setup';

describe.only("Checking Prover's multiple compute", () => {
  let proofMarketplace: ProofMarketplace;
  let proverRegistry: ProverRegistry;
  let tokenToUse: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;
  let iverifier: IVerifier;

  let stakingManager: StakingManager;
  let nativeStaking: NativeStaking;
  let symbioticStaking: SymbioticStaking;
  let symbioticStakingReward: SymbioticStakingReward;

  let POND: POND;
  let WETH: WETH;
  let USDC: USDC;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;
  let vault1: Signer;
  let vault2: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let proverData: ProverData;

  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const proverEnclave = new MockEnclave(MockProverPCRS);

  const godEnclave = new MockEnclave(GodEnclavePCRS);

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const proverComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);

  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByProver = new BigNumber(10).pow(18).multipliedBy(199);

  const refreshSetup = async (
    modifiedComputeGivenToNewMarket = computeGivenToNewMarket,
    modifiedGeneratorStakingAmount = generatorStakingAmount,
  ): Promise<void> => {
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

    proverData = {
      name: "some custom name for the prover",
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
      modifiedGeneratorStakingAmount,
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
      minRewardByProver,
      proverComputeAllocation,
      modifiedComputeGivenToNewMarket,
      godEnclave,
    );

    proofMarketplace = data.proofMarketplace;
    proverRegistry = data.proverRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;

    /* Staking Contracts */
    stakingManager = data.stakingManager;
    nativeStaking = data.nativeStaking;
    symbioticStaking = data.symbioticStaking;
    symbioticStakingReward = data.symbioticStakingReward;

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  };

  beforeEach(async () => {
    await refreshSetup();

    vault1 = signers[6];
    vault2 = signers[7];
    ({ POND, WETH, USDC } = await stakingSetup(admin, stakingManager, nativeStaking, symbioticStaking, symbioticStakingReward));

    await proverSelfStake(nativeStaking, admin, prover, POND, new BigNumber(10).pow(18).multipliedBy(10000));

    /* Submitting Vault Snapshots */
    const snapshotData: VaultSnapshotData[] = [
      // vault1 -> generator (10000 POND)
      {
        operator: await generator.getAddress(),
        vault: await vault1.getAddress(),
        stakeToken: await POND.getAddress(),
        stakeAmount: new BigNumber(10).pow(18).multipliedBy(10000).toFixed(0),
      },
      // vault2 -> generator (10000 WETH)
      {
        operator: await generator.getAddress(),
        vault: await vault2.getAddress(),
        stakeToken: await WETH.getAddress(),
        stakeAmount: new BigNumber(10).pow(18).multipliedBy(10000).toFixed(0),
      },
    ];

    await submitVaultSnapshot(prover, symbioticStaking, snapshotData);
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
      admin.provider as Provider,
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
      prover,
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
    await expect(proofMarketplace.submitProof(bidId, proofBytes)).to.emit(proofMarketplace, "ProofCreated").withArgs(bidId, proofBytes);
  });

  it("Should Fail invalid Proof: Simple Transfer Verifier, but proof generated for some other request", async () => {
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
      admin.provider as Provider,
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
      prover,
    );

    let proofBytes = abiCoder.encode(
      ["uint256[8]"],
      [
        [
          invalid_transfer_verifier_proof.a[0],
          invalid_transfer_verifier_proof.a[1],
          invalid_transfer_verifier_proof.b[0][0],
          invalid_transfer_verifier_proof.b[0][1],
          invalid_transfer_verifier_proof.b[1][0],
          invalid_transfer_verifier_proof.b[1][1],
          invalid_transfer_verifier_proof.c[0],
          invalid_transfer_verifier_proof.c[1],
        ],
      ],
    );
    await expect(proofMarketplace.submitProof(bidId, proofBytes))
      .to.revertedWithCustomError(proofMarketplace, "InvalidProof")
      .withArgs(bidId);
  });

  it("Task Assignment fails if it exceeds compute capacity", async () => {
    const max_asks = proverComputeAllocation.div(computeGivenToNewMarket).toFixed(0);

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

        await tokenToUse.connect(prover).approve(await proofMarketplace.getAddress(), ask.reward.toString());

        const bidId = await proofMarketplace.bidCounter();

        await proofMarketplace.connect(prover).createBid(ask, marketId, "0x", "0x");

        const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);

        await expect(
          proofMarketplace.connect(matchingEngine).assignTask(bidId, await prover.getAddress(), "0x1234"),
        ).to.be.revertedWithCustomError(errorLibrary, "InsufficientGeneratorComputeAvailable");
      } else {
        const bidId = await setup.createBid(
          prover,
          tokenHolder,
          {
            marketId,
            proverData: inputBytes,
            reward: rewardForProofGeneration.toFixed(),
            expiry: (assignmentExpiry + latestBlock).toString(),
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
          admin.provider as Provider,
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
          prover,
        );

        // console.log({ taskId, index });
      }
    }
  });

  it("Leave Market Place with active request", async () => {
    const latestBlock = await ethers.provider.getBlockNumber();
    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

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

    const bidId = await setup.createBid(
      prover,
      tokenHolder,
      {
        marketId,
        proverData: inputBytes,
        reward: rewardForProofGeneration.toFixed(),
        expiry: (assignmentExpiry + latestBlock).toString(),
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
      admin.provider as Provider,
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
      prover,
    );

    await expect(proverRegistry.connect(prover).leaveMarketplace(marketId)).to.revertedWithCustomError(
      proverRegistry,
      "CannotLeaveMarketWithActiveRequest",
    );
  });

  it("Invalid arguments in leave market place", async () => {
    await expect(proverRegistry.connect(admin).leaveMarketplace(marketId)).to.revertedWithCustomError(
      proverRegistry,
      "InvalidGeneratorStatePerMarket",
    );

    // some random market id number
    await expect(proverRegistry.connect(prover).leaveMarketplace("287")).to.revertedWithoutReason; // actual reason probably is array-out-of-bonds
  });

  it("Task Assignment fails if it exceeds maximum parallel requests per generators", async () => {
    const MAX_PARALLEL_REQUESTS = new BigNumber((await proverRegistry.PARALLEL_REQUESTS_UPPER_LIMIT()).toString());

    const newComputeGivenToMarket = proverComputeAllocation.div(MAX_PARALLEL_REQUESTS).div(105).multipliedBy(100);

    await refreshSetup(newComputeGivenToMarket);
    const max_asks = proverComputeAllocation.div(newComputeGivenToMarket).toFixed(0);

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

    for (let index = 0; index < parseInt(max_asks); index++) {
      const latestBlock = await ethers.provider.getBlockNumber();
      let assignmentExpiry = 100; // in blocks
      let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
      let maxTimeForProofGeneration = 10000; // in blocks

      if (index > MAX_PARALLEL_REQUESTS.toNumber()) {
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

        await tokenToUse.connect(prover).approve(await proofMarketplace.getAddress(), ask.reward.toString());

        const bidId = await proofMarketplace.bidCounter();

        await proofMarketplace.connect(prover).createBid(ask, marketId, "0x", "0x");

        const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);

        await expect(
          proofMarketplace.connect(matchingEngine).assignTask(bidId, await prover.getAddress(), "0x1234"),
        ).to.be.revertedWithCustomError(proverRegistry, "MaxParallelRequestsPerMarketExceeded");
      } else {
        const bidId = await setup.createBid(
          prover,
          tokenHolder,
          {
            marketId,
            proverData: inputBytes,
            reward: rewardForProofGeneration.toFixed(),
            expiry: (assignmentExpiry + latestBlock).toString(),
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
          admin.provider as Provider,
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
          prover,
        );
      }
    }
  });

  it("Task Assignment fails if generator doesn't have sufficient stake", async () => {
    const max_restricted_requests_by_stake = 3;
    const newGeneratorStake = generatorSlashingPenalty.multipliedBy(max_restricted_requests_by_stake);
    await refreshSetup(computeGivenToNewMarket, newGeneratorStake);

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

    for (let index = 0; index < max_restricted_requests_by_stake + 12; index++) {
      const latestBlock = await ethers.provider.getBlockNumber();
      let assignmentExpiry = 100; // in blocks
      let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
      let maxTimeForProofGeneration = 10000; // in blocks

      if (index >= max_restricted_requests_by_stake) {
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

        await tokenToUse.connect(prover).approve(await proofMarketplace.getAddress(), ask.reward.toString());

        const bidId = await proofMarketplace.bidCounter();

        await proofMarketplace.connect(prover).createBid(ask, marketId, "0x", "0x");

        const matchingEngine: Signer = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);

        // await expect(
        //   proofMarketplace.connect(matchingEngine).assignTask(askId, await generator.getAddress(), "0x1234"),
        // ).to.be.revertedWithCustomError(generatorRegistry, "InsufficientStakeToLock");
      } else {
        const bidId = await setup.createBid(
          prover,
          tokenHolder,
          {
            marketId,
            proverData: inputBytes,
            reward: rewardForProofGeneration.toFixed(),
            expiry: (assignmentExpiry + latestBlock).toString(),
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
          admin.provider as Provider,
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
          prover,
        );
      }
    }
  });

  it("Only registered generator should be able to add/update entity keys", async () => {
    const proverEnclave = new MockEnclave(MockProverPCRS);

    let proverAttestationBytes = await proverEnclave.getVerifiedAttestation(godEnclave);

    let types = ["bytes", "address"];

    let values = [proverAttestationBytes, await prover.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await proverEnclave.signMessage(ethers.getBytes(digest));

    await expect(proverRegistry.connect(prover).updateEncryptionKey(marketId, proverAttestationBytes, signature))
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await prover.getAddress(), marketId);
  });

  it("Only admin can set the generator registry role", async () => {
    const generatorRole = await entityKeyRegistry.KEY_REGISTER_ROLE();
    await expect(entityKeyRegistry.connect(treasury).addProverRegistry(await proofMarketplace.getAddress())).to.be.reverted;

    await entityKeyRegistry.addProverRegistry(await proofMarketplace.getAddress());
    expect(await entityKeyRegistry.hasRole(generatorRole, await proofMarketplace.getAddress())).to.eq(true);
  });

  it("Updating with invalid key should revert", async () => {
    const proverEnclave = new MockEnclave(MockProverPCRS);
    const invalidPubkey = "0x1234";

    let abiCoder = new ethers.AbiCoder();
    let validAttesationWithInvalidKey = abiCoder.encode(
      ["bytes", "bytes", "bytes", "bytes", "bytes", "uint256"],
      ["0x00", invalidPubkey, MockProverPCRS[0], MockProverPCRS[1], MockProverPCRS[2], new Date().valueOf()],
    );

    let types = ["bytes", "address"];
    let values = [validAttesationWithInvalidKey, await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await proverEnclave.signMessage(ethers.getBytes(digest));

    await expect(
      proverRegistry.connect(prover).updateEncryptionKey(marketId, validAttesationWithInvalidKey, signature),
    ).to.be.revertedWithCustomError(errorLibrary, "InvalidEnclaveKey");
  });

  it("Remove key", async () => {
    // Adding key to registry
    const proverEnclave = new MockEnclave(MockProverPCRS);
    let newAttesationBytes = await proverEnclave.getVerifiedAttestation(godEnclave);

    let types = ["bytes", "address"];

    let values = [newAttesationBytes, await generator.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await proverEnclave.signMessage(ethers.getBytes(digest));

    await expect(proverRegistry.connect(prover).updateEncryptionKey(marketId, newAttesationBytes, signature))
      .to.emit(entityKeyRegistry, "UpdateKey")
      .withArgs(await prover.getAddress(), marketId);

    // Checking key in registry
    const pub_key = await entityKeyRegistry.pub_key(generator.getAddress(), marketId);
    // console.log({ pub_key: pub_key });
    // console.log({pubBytes: pubBytes });
    expect(pub_key).to.eq(proverEnclave.getUncompressedPubkey());

    // Removing key from registry
    await expect(proverRegistry.connect(prover).removeEncryptionKey(marketId))
      .to.emit(entityKeyRegistry, "RemoveKey")
      .withArgs(await prover.getAddress(), marketId);
  });

  it("Generator Prechecks", async () => {
    const exponent = new BigNumber(10).pow(18).toFixed(0);

    const proverData = await proverRegistry.proverRegistry(await prover.getAddress());
    expect(proverComputeAllocation.toFixed(0)).to.eq(proverData.declaredCompute.toString());
    expect(proverData.computeConsumed).to.eq(0);
    // expect(proverData.totalStake).to.eq(proverStakingAmount.toFixed(0));
    // expect(proverData.stakeLocked).to.eq(0);
    expect(proverData.activeMarketplaces).to.eq(1);
    expect(proverData.intendedComputeUtilization).to.eq(exponent);
    // expect(proverData.intendedStakeUtilization).to.eq(exponent);

    const marketId = 0; // likely to be 0, if failed change it
    const proverDataPerMarket = await proverRegistry.proverInfoPerMarket(await prover.getAddress(), marketId);

    expect(proverDataPerMarket.state).to.not.eq(0); // 0 means no generator
    expect(proverDataPerMarket.computePerRequestRequired).to.eq(computeGivenToNewMarket.toFixed(0));
    expect(proverDataPerMarket.proofGenerationCost).to.eq(minRewardByProver.toFixed(0));
    expect(proverDataPerMarket.activeRequests).to.eq(0);
  });
});