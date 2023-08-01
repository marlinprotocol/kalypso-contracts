import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  GeneratorRegistry,
  GeneratorRegistry__factory,
  MockToken,
  MockToken__factory,
  MockVerifier,
  MockVerifier__factory,
  ProofMarketPlace,
  ProofMarketPlace__factory,
} from "../typechain-types";
import { bytesToHexString, generateRandomBytes } from "../helpers";

describe("Proof market place", () => {
  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let marketCreator: Signer;

  let marketPlaceAddress: Signer;

  let mockToken: MockToken;
  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);

  let generatorStakingAmount = new BigNumber(10).pow(21).multipliedBy(6);
  let generatorSlashingPenalty = new BigNumber(10).pow(20).multipliedBy(2);

  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let mockVerifier: MockVerifier;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[1];
    tokenHolder = signers[2];
    treasury = signers[3];
    marketCreator = signers[4];

    marketPlaceAddress = signers[8];

    mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    mockVerifier = await new MockVerifier__factory(admin).deploy();

    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [
        await mockToken.getAddress(),
        generatorStakingAmount.toFixed(),
        generatorSlashingPenalty.toFixed(),
      ],
      initializer: false,
    });
    generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), signers[0]);

    const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
    const proxy = await upgrades.deployProxy(
      ProofMarketPlace,
      [
        await admin.getAddress(),
        await mockToken.getAddress(),
        await treasury.getAddress(),
        marketCreationCost.toFixed(),
        await generatorRegistry.getAddress(),
      ],
      { kind: "uups", constructorArgs: [] },
    );
    proofMarketPlace = ProofMarketPlace__factory.connect(await proxy.getAddress(), signers[0]);

    await generatorRegistry.initialize(await admin.getAddress(), await proofMarketPlace.getAddress());

    expect(ethers.isAddress(await proofMarketPlace.getAddress())).is.true;
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());
  });

  it("Create Market", async () => {
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    const marketId = ethers.keccak256(marketBytes);

    await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());
    await expect(
      proofMarketPlace.connect(marketCreator).createMarketPlace(marketBytes, await mockVerifier.getAddress()),
    )
      .to.emit(proofMarketPlace, "MarketPlaceCreated")
      .withArgs(marketId);
  });

  it("Update Marketplace address", async () => {
    await proofMarketPlace
      .connect(admin)
      .grantRole(await proofMarketPlace.MATCHING_ENGINE_ROLE(), await marketPlaceAddress.getAddress());

    expect(
      await proofMarketPlace.hasRole(
        await proofMarketPlace.MATCHING_ENGINE_ROLE(),
        await marketPlaceAddress.getAddress(),
      ),
    ).to.be.true;
  });

  describe("Ask", () => {
    let prover: Signer;
    let reward = new BigNumber(10).pow(20).multipliedBy(3);
    let marketId: string;

    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 1000; // in blocks
    let maxTimeForProofGeneration = 10000; // in blocks

    beforeEach(async () => {
      prover = signers[5];
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

      marketId = ethers.keccak256(marketBytes);

      await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());
      await proofMarketPlace.connect(marketCreator).createMarketPlace(marketBytes, await mockVerifier.getAddress());
    });

    it("Create", async () => {
      await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

      const latestBlock = await ethers.provider.getBlockNumber();

      const askIdToBeGenerated = await proofMarketPlace.askCounter();

      await expect(
        proofMarketPlace.connect(prover).createAsk({
          marketId,
          proverData: proverBytes,
          reward: reward.toFixed(),
          expiry: assignmentExpiry + latestBlock,
          timeTakenForProofGeneration,
          deadline: latestBlock + maxTimeForProofGeneration,
        }),
      )
        .to.emit(proofMarketPlace, "AskCreated")
        .withArgs(askIdToBeGenerated);
    });

    describe("Generator", () => {
      let generatorData: string;
      let generator: Signer;

      beforeEach(async () => {
        generator = await signers[12];
        generatorData = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
        await mockToken.connect(tokenHolder).transfer(await generator.getAddress(), generatorStakingAmount.toFixed());

        await mockToken
          .connect(generator)
          .approve(await generatorRegistry.getAddress(), generatorStakingAmount.toFixed());
        // amount locked can be anything, it get overrides within the contract
      });

      it("Check generator data", async () => {
        await expect(
          generatorRegistry
            .connect(generator)
            .register({ rewardAddress: await generator.getAddress(), generatorData, amountLocked: 0 }, marketId),
        )
          .to.emit(generatorRegistry, "RegisteredGenerator")
          .withArgs(await generator.getAddress(), marketId);

        const rewardAddress = (await generatorRegistry.generatorRegistry(await generator.getAddress(), marketId))
          .generator.rewardAddress;
        expect(rewardAddress).to.eq(await generator.getAddress());
      });

      describe("Task", () => {
        let proverBytes: string;
        let latestBlock: number;

        let askId: BigNumber;
        beforeEach(async () => {
          proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          latestBlock = await ethers.provider.getBlockNumber();

          await proofMarketPlace
            .connect(admin)
            .grantRole(await proofMarketPlace.MATCHING_ENGINE_ROLE(), await marketPlaceAddress.getAddress());

          askId = new BigNumber((await proofMarketPlace.askCounter()).toString());

          await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
          await proofMarketPlace.connect(prover).createAsk({
            marketId,
            proverData: proverBytes,
            reward: reward.toFixed(),
            expiry: latestBlock + assignmentExpiry,
            timeTakenForProofGeneration,
            deadline: latestBlock + maxTimeForProofGeneration,
          });

          await generatorRegistry
            .connect(generator)
            .register({ rewardAddress: await generator.getAddress(), generatorData, amountLocked: 0 }, marketId);
        });

        it("Matching engine assings", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          await expect(
            proofMarketPlace.connect(marketPlaceAddress).assignTask(askId.toString(), await generator.getAddress()),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, taskId);
        });

        describe("Submit Proof", () => {
          let proof: string;
          let taskId: string;

          beforeEach(async () => {
            proof = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

            taskId = (await proofMarketPlace.taskCounter()).toString();
            await proofMarketPlace
              .connect(marketPlaceAddress)
              .assignTask(askId.toString(), await generator.getAddress());
          });

          it("submit proof", async () => {
            await proofMarketPlace.submitProof(taskId, proof);
          });
        });
      });
    });
  });
});
