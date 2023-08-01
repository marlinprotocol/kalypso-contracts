import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  Error,
  Error__factory,
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

import { mine } from "@nomicfoundation/hardhat-network-helpers";

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

  let minRewardForGenerator = new BigNumber(10).pow(18).multipliedBy(100);

  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let mockVerifier: MockVerifier;

  let errorLibrary: Error;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[1];
    tokenHolder = signers[2];
    treasury = signers[3];
    marketCreator = signers[4];

    marketPlaceAddress = signers[8];

    errorLibrary = await new Error__factory(admin).deploy();

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

    expect(await proofMarketPlace.getMarketVerifier(marketId)).to.eq(await mockVerifier.getAddress());
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

    it("Create Ask Request", async () => {
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
          proverRefundAddress: await prover.getAddress(),
        }),
      )
        .to.emit(proofMarketPlace, "AskCreated")
        .withArgs(askIdToBeGenerated);

      expect((await proofMarketPlace.listOfAsk(askIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    it("Should Fail: when try creating market in invalid market", async () => {
      await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

      const latestBlock = await ethers.provider.getBlockNumber();

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 2)); // 10 MB
      const invalidMarketId = ethers.keccak256(marketBytes);

      await expect(
        proofMarketPlace.connect(prover).createAsk({
          marketId: invalidMarketId,
          proverData: proverBytes,
          reward: reward.toFixed(),
          expiry: assignmentExpiry + latestBlock,
          timeTakenForProofGeneration,
          deadline: latestBlock + maxTimeForProofGeneration,
          proverRefundAddress: await prover.getAddress(),
        }),
      ).to.be.revertedWith(await errorLibrary.DOES_NOT_EXISTS());
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
          generatorRegistry.connect(generator).register(
            {
              rewardAddress: await generator.getAddress(),
              generatorData,
              amountLocked: 0,
              minReward: minRewardForGenerator.toFixed(),
            },
            marketId,
          ),
        )
          .to.emit(generatorRegistry, "RegisteredGenerator")
          .withArgs(await generator.getAddress(), marketId);

        const rewardAddress = (await generatorRegistry.generatorRegistry(await generator.getAddress(), marketId))
          .generator.rewardAddress;
        expect(rewardAddress).to.eq(await generator.getAddress());

        expect((await generatorRegistry.generatorRegistry(await generator.getAddress(), marketId)).state).to.eq(1); //1 means JOINED
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
            proverRefundAddress: await prover.getAddress(),
          });

          await generatorRegistry.connect(generator).register(
            {
              rewardAddress: await generator.getAddress(),
              generatorData,
              amountLocked: 0,
              minReward: minRewardForGenerator.toFixed(),
            },
            marketId,
          );
        });

        it("Matching engine assings", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          await expect(
            proofMarketPlace.connect(marketPlaceAddress).assignTask(askId.toString(), await generator.getAddress()),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, taskId);

          expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED
          expect((await generatorRegistry.generatorRegistry(await generator.getAddress(), marketId)).state).to.eq(3); // 3 means WIP
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

            expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect((await generatorRegistry.generatorRegistry(await generator.getAddress(), marketId)).state).to.eq(1); // 1 means JOINED and idle now
          });

          describe("Failed submiited proof", () => {
            let slasher: Signer;

            beforeEach(async () => {
              slasher = signers[19];
              await mine(maxTimeForProofGeneration);
            });

            it("State should be deadline crossed", async () => {
              expect(await proofMarketPlace.getAskState(askId.toString())).to.eq(5);
            });

            it("When deadline is crossed, it is slashable", async () => {
              await expect(proofMarketPlace.connect(slasher).slashGenerator(taskId, await slasher.getAddress()))
                .to.emit(proofMarketPlace, "ProofNotGenerated")
                .withArgs(taskId);
            });
          });
        });
      });
    });
  });
});
