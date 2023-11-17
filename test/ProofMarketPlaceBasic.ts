import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  Error,
  Error__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
  MockAttestationVerifier__factory,
  MockToken,
  MockToken__factory,
  MockVerifier,
  MockVerifier__factory,
  ProofMarketPlace,
  ProofMarketPlace__factory,
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
} from "../typechain-types";
import { bytesToHexString, generateRandomBytes, jsonToBytes, splitHexString } from "../helpers";

import { mine } from "@nomicfoundation/hardhat-network-helpers";
import * as secret from "../data/transferVerifier/1/secret.json";

describe("Proof market place", () => {
  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let marketCreator: Signer;

  let marketPlaceAddress: Signer;

  let mockToken: MockToken;
  let platformToken: MockToken;

  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);

  let generatorStakingAmount = new BigNumber(10).pow(21).multipliedBy(6);

  let minRewardForGenerator = new BigNumber(10).pow(18).multipliedBy(100);

  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let mockVerifier: MockVerifier;

  let errorLibrary: Error;

  const enclave_key_attestation_bytes = "0x";
  const exponent = new BigNumber(10).pow(18);

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[1];
    tokenHolder = signers[2];
    treasury = signers[3];
    marketCreator = signers[4];

    marketPlaceAddress = signers[8];

    errorLibrary = await new Error__factory(admin).deploy();

    mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    platformToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    mockVerifier = await new MockVerifier__factory(admin).deploy();

    const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
    const entityRegistry = await new EntityKeyRegistry__factory(admin).deploy(
      await mockAttestationVerifier.getAddress(),
      await admin.getAddress()
    );

    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [await mockToken.getAddress()],
      initializer: false,
    });
    generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), signers[0]);

    const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
    const proxy = await upgrades.deployProxy(ProofMarketPlace, [await admin.getAddress()], {
      kind: "uups",
      constructorArgs: [
        await mockToken.getAddress(),
        await platformToken.getAddress(),
        marketCreationCost.toString(),
        await treasury.getAddress(),
        await generatorRegistry.getAddress(),
        await entityRegistry.getAddress(),
      ],
    });
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
      proofMarketPlace
        .connect(marketCreator)
        .createMarketPlace(marketBytes, await mockVerifier.getAddress(), exponent.div(100).toFixed(0)),
    )
      .to.emit(proofMarketPlace, "MarketPlaceCreated")
      .withArgs(marketId);

    expect(await proofMarketPlace.verifier(marketId)).to.eq(await mockVerifier.getAddress());
  });

  it("Update Marketplace address", async () => {
    await proofMarketPlace
      .connect(admin)
      ["grantRole(bytes32,address,bytes)"](
        await proofMarketPlace.MATCHING_ENGINE_ROLE(),
        await marketPlaceAddress.getAddress(),
        enclave_key_attestation_bytes,
      );

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

    const computeUnitsRequired = 10; // temporary absolute number

    beforeEach(async () => {
      prover = signers[5];
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

      marketId = ethers.keccak256(marketBytes);

      await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());
      await proofMarketPlace
        .connect(marketCreator)
        .createMarketPlace(marketBytes, await mockVerifier.getAddress(), exponent.div(100).toFixed(0));
    });

    it("Create Ask Request", async () => {
      const latestBlock = await ethers.provider.getBlockNumber();

      const askIdToBeGenerated = await proofMarketPlace.askCounter();

      await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());

      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const askRequest = {
        marketId,
        proverData: proverBytes,
        reward: reward.toFixed(),
        expiry: assignmentExpiry + latestBlock,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      };

      const secretInfo = "0x2345";
      const aclInfo = "0x21";

      const platformFee = await proofMarketPlace.getPlatformFee(askRequest, secretInfo, aclInfo);
      await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee);
      await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee);

      await expect(proofMarketPlace.connect(prover).createAsk(askRequest, false, 0, secretInfo, aclInfo))
        .to.emit(proofMarketPlace, "AskCreated")
        .withArgs(askIdToBeGenerated, false, "0x2345", "0x21")
        .to.emit(mockToken, "Transfer")
        .withArgs(await prover.getAddress(), await proofMarketPlace.getAddress(), reward)
        .to.emit(platformToken, "Transfer")
        .withArgs(await prover.getAddress(), await treasury.getAddress(), platformFee);

      expect((await proofMarketPlace.listOfAsk(askIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    it("Should Fail: when try creating market in invalid market", async () => {
      await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes()).toString()).multipliedBy(
        (proverBytes.length - 2) / 2,
      );
      await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
      await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());

      const latestBlock = await ethers.provider.getBlockNumber();

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 2)); // 10 MB
      const invalidMarketId = ethers.keccak256(marketBytes);

      await expect(
        proofMarketPlace.connect(prover).createAsk(
          {
            marketId: invalidMarketId,
            proverData: proverBytes,
            reward: reward.toFixed(),
            expiry: assignmentExpiry + latestBlock,
            timeTakenForProofGeneration,
            deadline: latestBlock + maxTimeForProofGeneration,
            refundAddress: await prover.getAddress(),
          },
          false,
          0,
          "0x",
          "0x",
        ),
      ).to.be.revertedWith(await errorLibrary.INVALID_MARKET());
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
            .register(await generator.getAddress(), computeUnitsRequired, generatorData),
        )
          .to.emit(generatorRegistry, "RegisteredGenerator")
          .withArgs(await generator.getAddress());
        await expect(
          generatorRegistry.connect(generator).stake(await generator.getAddress(), generatorStakingAmount.toFixed(0)),
        )
          .to.emit(generatorRegistry, "AddedStake")
          .withArgs(await generator.getAddress(), generatorStakingAmount.toFixed(0));

        await expect(
          generatorRegistry
            .connect(generator)
            .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100),
        )
          .to.emit(generatorRegistry, "JoinedMarketPlace")
          .withArgs(await generator.getAddress(), marketId, computeUnitsRequired);

        const rewardAddress = (await generatorRegistry.generatorRegistry(await generator.getAddress())).rewardAddress;
        expect(rewardAddress).to.eq(await generator.getAddress());

        expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(1); //1 means JOINED
      });

      it("leave market place", async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), computeUnitsRequired, generatorData);
        await generatorRegistry
          .connect(generator)
          .stake(await generator.getAddress(), generatorStakingAmount.toFixed(0));
        await generatorRegistry
          .connect(generator)
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100);

        await expect(generatorRegistry.connect(generator).leaveMarketPlace(marketId))
          .to.emit(generatorRegistry, "LeftMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("leave multiple markets", async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), computeUnitsRequired, generatorData);
        await generatorRegistry
          .connect(generator)
          .stake(await generator.getAddress(), generatorStakingAmount.toFixed(0));
        await generatorRegistry
          .connect(generator)
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100);

        await expect(generatorRegistry.connect(generator).leaveMarketPlaces([marketId]))
          .to.emit(generatorRegistry, "LeftMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("Can't de-register if generator is active part of proof market", async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), computeUnitsRequired, generatorData);
        await generatorRegistry
          .connect(generator)
          .stake(await generator.getAddress(), generatorStakingAmount.toFixed(0));
        await generatorRegistry
          .connect(generator)
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100);

        await expect(generatorRegistry.connect(generator).deregister(await generator.getAddress())).to.be.revertedWith(
          await errorLibrary.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET(),
        );
      });

      it("Deregister generator data", async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), computeUnitsRequired, marketId);

        await expect(generatorRegistry.connect(generator).deregister(await generator.getAddress()))
          .to.emit(generatorRegistry, "DeregisteredGenerator")
          .withArgs(await generator.getAddress());
      });

      it("extra stash can be added to generator by anyone", async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), computeUnitsRequired, generatorData);

        const extraStash = "112987298347983";
        await mockToken.connect(tokenHolder).approve(await generatorRegistry.getAddress(), extraStash);

        await expect(generatorRegistry.connect(tokenHolder).stake(await generator.getAddress(), extraStash))
          .to.emit(generatorRegistry, "AddedStake")
          .withArgs(await generator.getAddress(), extraStash)
          .to.emit(mockToken, "Transfer")
          .withArgs(await tokenHolder.getAddress(), await generatorRegistry.getAddress(), extraStash);
      });

      describe("Task", () => {
        let proverBytes: string;
        let latestBlock: number;

        let askId: BigNumber;
        beforeEach(async () => {
          proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes()).toString()).multipliedBy(
            (proverBytes.length - 2) / 2,
          );
          await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
          await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());

          latestBlock = await ethers.provider.getBlockNumber();

          await proofMarketPlace
            .connect(admin)
            ["grantRole(bytes32,address,bytes)"](
              await proofMarketPlace.MATCHING_ENGINE_ROLE(),
              await marketPlaceAddress.getAddress(),
              enclave_key_attestation_bytes,
            );

          askId = new BigNumber((await proofMarketPlace.askCounter()).toString());

          await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
          await proofMarketPlace.connect(prover).createAsk(
            {
              marketId,
              proverData: proverBytes,
              reward: reward.toFixed(),
              expiry: latestBlock + assignmentExpiry,
              timeTakenForProofGeneration,
              deadline: latestBlock + maxTimeForProofGeneration,
              refundAddress: await prover.getAddress(),
            },
            false,
            0,
            "0x",
            "0x",
          );

          await generatorRegistry
            .connect(generator)
            .register(await generator.getAddress(), computeUnitsRequired, generatorData);
          await generatorRegistry
            .connect(generator)
            .stake(await generator.getAddress(), generatorStakingAmount.toFixed(0));
          await generatorRegistry
            .connect(generator)
            .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100);
        });

        it("Matching engine assings", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          await expect(
            proofMarketPlace
              .connect(marketPlaceAddress)
              .assignTask(askId.toString(), taskId, await generator.getAddress(), "0x1234"),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, taskId, await generator.getAddress(), "0x1234");

          expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(
            1,
          );

          // but via function it should be 2
          const data = await generatorRegistry.getGeneratorState(await generator.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching engine should assign tasks using relayer", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          const newTaskId = taskId;

          const types = ["uint256", "uint256", "address", "bytes"];

          const values = [askId.toFixed(0), newTaskId.toString(), await generator.getAddress(), "0x1234"];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await marketPlaceAddress.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketPlace
              .connect(someRandomRelayer)
              .relayAssignTask(askId.toString(), taskId, await generator.getAddress(), "0x1234", signature),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, taskId, await generator.getAddress(), "0x1234");

          expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(
            1,
          );

          // but via function it should be 2
          const data = await generatorRegistry.getGeneratorState(await generator.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine should assign using relayers [multiple tasks]", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          const newTaskId = taskId;

          const types = ["uint256[]", "uint256[]", "address[]", "bytes[]"];

          const values = [[askId.toFixed(0)], [newTaskId.toString()], [await generator.getAddress()], ["0x1234"]];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await marketPlaceAddress.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketPlace
              .connect(someRandomRelayer)
              .relayBatchAssignTasks(
                [askId.toString()],
                [taskId],
                [await generator.getAddress()],
                ["0x1234"],
                signature,
              ),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, taskId, await generator.getAddress(), "0x1234");

          expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(
            1,
          );

          // but via function it should be 2
          const data = await generatorRegistry.getGeneratorState(await generator.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine can't assign more than vcpus", async () => {
          const taskId = await proofMarketPlace.taskCounter();
          await proofMarketPlace
            .connect(marketPlaceAddress)
            .assignTask(askId.toString(), taskId, await generator.getAddress(), "0x1234");

          let anotherAskId = new BigNumber((await proofMarketPlace.askCounter()).toString());
          let anotherProverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes()).toString()).multipliedBy(
            (anotherProverBytes.length - 2) / 2,
          );
          await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
          await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());

          await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());
          await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
          await proofMarketPlace.connect(prover).createAsk(
            {
              marketId,
              proverData: anotherProverBytes,
              reward: reward.toFixed(),
              expiry: latestBlock + assignmentExpiry,
              timeTakenForProofGeneration,
              deadline: latestBlock + maxTimeForProofGeneration,
              refundAddress: await prover.getAddress(),
            },
            false,
            0,
            "0x",
            "0x",
          );

          await expect(
            proofMarketPlace
              .connect(marketPlaceAddress)
              .assignTask(
                anotherAskId.toString(),
                new BigNumber(taskId.toString()).plus(1).toFixed(),
                await generator.getAddress(),
                "0x1234",
              ),
          ).to.be.revertedWith(await errorLibrary.ASSIGN_ONLY_TO_IDLE_GENERATORS());
        });

        it("Should fail: Matching engine will not be able to assign task if ask is expired", async () => {
          await mine(assignmentExpiry);
          const taskId = await proofMarketPlace.taskCounter();
          await expect(
            proofMarketPlace
              .connect(marketPlaceAddress)
              .assignTask(askId.toString(), taskId, await generator.getAddress(), "0x"),
          ).to.be.rejectedWith(await errorLibrary.SHOULD_BE_IN_CREATE_STATE());
        });

        it("Can cancel ask once the ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(proofMarketPlace.connect(admin).cancelAsk(askId.toString()))
            .to.emit(proofMarketPlace, "AskCancelled")
            .withArgs(askId)
            .to.emit(mockToken, "Transfer")
            .withArgs(await proofMarketPlace.getAddress(), await prover.getAddress(), reward.toFixed());
        });

        describe("Submit Proof", () => {
          let proof: string;
          let taskId: string;

          beforeEach(async () => {
            proof = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

            taskId = (await proofMarketPlace.taskCounter()).toString();
            await proofMarketPlace
              .connect(marketPlaceAddress)
              .assignTask(askId.toString(), taskId, await generator.getAddress(), "0x");
          });

          it("submit proof", async () => {
            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await expect(proofMarketPlace.submitProof(taskId, proof))
              .to.emit(proofMarketPlace, "ProofCreated")
              .withArgs(askId, taskId, proof)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect(
              (await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state,
            ).to.eq(1); // 1 means JOINED and idle now
          });

          it("Submit Proof via array", async () => {
            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await expect(proofMarketPlace.submitProofs([taskId], [proof]))
              .to.emit(proofMarketPlace, "ProofCreated")
              .withArgs(askId, taskId, proof)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect(
              (await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state,
            ).to.eq(1); // 1 means JOINED and idle now
          });

          it("Generator can ignore the request", async () => {
            await expect(proofMarketPlace.connect(generator).discardRequest(taskId))
              .to.emit(proofMarketPlace, "ProofNotGenerated")
              .withArgs(askId, taskId);
          });

          it("Can't slash request before deadline", async () => {
            let slasher = signers[19];
            await expect(
              proofMarketPlace.connect(slasher).slashGenerator(taskId, await slasher.getAddress()),
            ).to.be.revertedWith(await errorLibrary.SHOULD_BE_IN_CROSSED_DEADLINE_STATE());
          });

          describe("Failed submiited proof", () => {
            let slasher: Signer;

            beforeEach(async () => {
              slasher = signers[19];
              await mine(maxTimeForProofGeneration);
            });

            it("State should be deadline crossed", async () => {
              expect(await proofMarketPlace.getAskState(askId.toString())).to.eq(5); // 5 means deadline crossed
            });

            it("When deadline is crossed, it is slashable", async () => {
              await expect(proofMarketPlace.connect(slasher).slashGenerator(taskId, await slasher.getAddress()))
                .to.emit(proofMarketPlace, "ProofNotGenerated")
                .withArgs(askId, taskId);
            });
          });
        });
      });
    });
  });
});
