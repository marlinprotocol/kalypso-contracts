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
  ProofMarketplace,
  ProofMarketplace__factory,
  EntityKeyRegistry__factory,
  Dispute__factory,
  EntityKeyRegistry,
} from "../typechain-types";

import {
  MockEnclave,
  MockGeneratorPCRS,
  MockIVSPCRS,
  MockMEPCRS,
  NO_ENCLAVE_ID,
  bytesToHexString,
  generateRandomBytes,
  skipBlocks,
} from "../helpers";

import { mine } from "@nomicfoundation/hardhat-network-helpers";

describe("Proof market place", () => {
  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let marketCreator: Signer;

  let mockToken: MockToken;

  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);

  let generatorStakingAmount = new BigNumber(10).pow(21).multipliedBy(6);

  let minRewardForGenerator = new BigNumber(10).pow(18).multipliedBy(100);

  let proofMarketplace: ProofMarketplace;
  let generatorRegistry: GeneratorRegistry;
  let entityRegistry: EntityKeyRegistry;
  let mockVerifier: MockVerifier;

  let errorLibrary: Error;

  const exponent = new BigNumber(10).pow(18);

  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const ivsEnclave = new MockEnclave(MockIVSPCRS);

  let matchingEngineSigner: Signer;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[1];
    tokenHolder = signers[2];
    treasury = signers[3];
    marketCreator = signers[4];

    matchingEngineSigner = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);
    await admin.sendTransaction({ to: matchingEngineEnclave.getAddress(), value: "1000000000000000000" });

    errorLibrary = await new Error__factory(admin).deploy();

    mockToken = await new MockToken__factory(admin).deploy(
      await tokenHolder.getAddress(),
      tokenSupply.toFixed(),
      "Payment Token",
      "PT",
    );
    mockVerifier = await new MockVerifier__factory(admin).deploy();

    const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
    const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
    const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
      kind: "uups",
      constructorArgs: [await mockAttestationVerifier.getAddress()],
    });
    entityRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [await mockToken.getAddress(), await entityRegistry.getAddress()],
      initializer: false,
    });
    generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), signers[0]);

    const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
    const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
      kind: "uups",
      constructorArgs: [
        await mockToken.getAddress(),
        marketCreationCost.toString(),
        await treasury.getAddress(),
        await generatorRegistry.getAddress(),
        await entityRegistry.getAddress(),
      ],
      initializer: false,
    });

    proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), signers[0]);

    const dispute = await new Dispute__factory(admin).deploy(await entityRegistry.getAddress());

    await generatorRegistry.initialize(await admin.getAddress(), await proofMarketplace.getAddress());
    await proofMarketplace.initialize(await admin.getAddress());

    expect(ethers.isAddress(await proofMarketplace.getAddress())).is.true;
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

    await entityRegistry
      .connect(admin)
      .grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proofMarketplace.getAddress());

    await entityRegistry
      .connect(admin)
      .grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await generatorRegistry.getAddress());

    await proofMarketplace.connect(admin).grantRole(await proofMarketplace.UPDATER_ROLE(), await admin.getAddress());
  });

  it("Create Market", async () => {
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    const marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

    await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

    await expect(
      proofMarketplace
        .connect(marketCreator)
        .createMarketplace(
          marketBytes,
          await mockVerifier.getAddress(),
          exponent.div(100).toFixed(0),
          new MockEnclave().getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        ),
    )
      .to.emit(proofMarketplace, "MarketplaceCreated")
      .withArgs(marketId);

    expect((await proofMarketplace.marketData(marketId)).verifier).to.eq(await mockVerifier.getAddress());
  });

  it("Update Marketplace address", async () => {
    let attestationBytes = await matchingEngineEnclave.getVerifiedAttestation(matchingEngineEnclave);

    let types = ["bytes", "address"];
    let values = [attestationBytes, await proofMarketplace.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

    await proofMarketplace.connect(admin).setMatchingEngineImage(matchingEngineEnclave.getPcrRlp());
    await proofMarketplace.connect(admin).verifyMatchingEngine(attestationBytes, signature);

    expect(
      await entityRegistry.allowOnlyVerified(matchingEngineEnclave.getAddress(), matchingEngineEnclave.getImageId()),
    ).to.be.true;
  });

  it("Update Marketplace address with timeout attesation should fail", async () => {
    const oldtimestamp = 1000;
    let attestationBytes = await matchingEngineEnclave.getVerifiedAttestation(matchingEngineEnclave, oldtimestamp);

    let types = ["bytes", "address"];
    let values = [attestationBytes, await proofMarketplace.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

    await proofMarketplace.connect(admin).setMatchingEngineImage(matchingEngineEnclave.getPcrRlp());
    await expect(proofMarketplace.connect(admin).verifyMatchingEngine(attestationBytes, signature)).to.be.revertedWith(
      "AA:VK-Attestation too old",
    );
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

      marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

      await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

      await proofMarketplace.connect(marketCreator).createMarketplace(
        marketBytes,
        await mockVerifier.getAddress(),
        exponent.div(100).toFixed(0),
        new MockEnclave().getPcrRlp(), // no pcrs means not enclave
        ivsEnclave.getPcrRlp(),
      );

      let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
      await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
    });

    it("Create Ask Request", async () => {
      const latestBlock = await ethers.provider.getBlockNumber();

      const askIdToBeGenerated = await proofMarketplace.askCounter();

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

      await proofMarketplace.connect(admin).grantRole(await proofMarketplace.UPDATER_ROLE(), await admin.getAddress());
      await proofMarketplace.connect(admin).updateCostPerBytes(1, 1000);

      const platformFee = await proofMarketplace.getPlatformFee(1, askRequest, secretInfo, aclInfo);
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee);

      await mockToken
        .connect(prover)
        .approve(await proofMarketplace.getAddress(), new BigNumber(platformFee.toString()).plus(reward).toFixed());

      await expect(proofMarketplace.connect(prover).createAsk(askRequest, 1, secretInfo, aclInfo))
        .to.emit(proofMarketplace, "AskCreated")
        .withArgs(askIdToBeGenerated, true, "0x2345", "0x21")
        .to.emit(mockToken, "Transfer")
        .withArgs(
          await prover.getAddress(),
          await proofMarketplace.getAddress(),
          new BigNumber(platformFee.toString()).plus(reward),
        );

      expect((await proofMarketplace.listOfAsk(askIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    it("Should Fail: when try creating market in invalid market", async () => {
      await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const platformFee = new BigNumber((await proofMarketplace.costPerInputBytes(1)).toString()).multipliedBy(
        (proverBytes.length - 2) / 2,
      );

      const latestBlock = await ethers.provider.getBlockNumber();

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 2)); // 10 MB
      const invalidMarketId = ethers.keccak256(marketBytes);

      await expect(
        proofMarketplace.connect(prover).createAsk(
          {
            marketId: invalidMarketId,
            proverData: proverBytes,
            reward: reward.toFixed(),
            expiry: assignmentExpiry + latestBlock,
            timeTakenForProofGeneration,
            deadline: latestBlock + maxTimeForProofGeneration,
            refundAddress: await prover.getAddress(),
          },
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
            .register(
              await generator.getAddress(),
              computeUnitsRequired,
              generatorStakingAmount.toFixed(0),
              generatorData,
            ),
        )
          .to.emit(generatorRegistry, "RegisteredGenerator")
          .withArgs(await generator.getAddress(), computeUnitsRequired, generatorStakingAmount.toFixed(0));

        let generatorEnclave = new MockEnclave(MockGeneratorPCRS);
        await expect(
          generatorRegistry
            .connect(generator)
            .joinMarketplace(
              marketId,
              computeUnitsRequired,
              minRewardForGenerator.toFixed(),
              100,
              false,
              await generatorEnclave.getVerifiedAttestation(generatorEnclave),
              "0x",
            ),
        )
          .to.emit(generatorRegistry, "JoinedMarketplace")
          .withArgs(await generator.getAddress(), marketId, computeUnitsRequired);

        const rewardAddress = (await generatorRegistry.generatorRegistry(await generator.getAddress())).rewardAddress;
        expect(rewardAddress).to.eq(await generator.getAddress());

        expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(1); //1 means JOINED
      });

      it("request for market place exit", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).requestForExitMarketplace(marketId))
          .to.emit(generatorRegistry, "RequestExitMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("request for market place exit: array", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).requestForExitMarketplaces([marketId]))
          .to.emit(generatorRegistry, "RequestExitMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("leave market place", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).leaveMarketplace(marketId))
          .to.emit(generatorRegistry, "LeftMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("leave multiple markets", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).leaveMarketplaces([marketId]))
          .to.emit(generatorRegistry, "LeftMarketplace")
          .withArgs(await generator.getAddress(), marketId);
      });

      it("Can't de-register if generator is active part of proof market", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).deregister(await generator.getAddress())).to.be.revertedWith(
          await errorLibrary.CAN_NOT_LEAVE_WITH_ACTIVE_MARKET(),
        );
      });

      it("Deregister generator data", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await expect(generatorRegistry.connect(generator).deregister(await generator.getAddress()))
          .to.emit(generatorRegistry, "DeregisteredGenerator")
          .withArgs(await generator.getAddress());
      });

      it("extra stash can be added to generator by anyone", async () => {
        await generatorRegistry
          .connect(generator)
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        const extraStash = "112987298347983";
        await mockToken.connect(tokenHolder).approve(await generatorRegistry.getAddress(), extraStash);

        await expect(generatorRegistry.connect(tokenHolder).stake(await generator.getAddress(), extraStash))
          .to.emit(generatorRegistry, "AddedStake")
          .withArgs(await generator.getAddress(), extraStash)
          .to.emit(mockToken, "Transfer")
          .withArgs(await tokenHolder.getAddress(), await generatorRegistry.getAddress(), extraStash);
      });

      describe("Generator After Staking", () => {
        beforeEach(async () => {
          await generatorRegistry
            .connect(generator)
            .register(
              await generator.getAddress(),
              computeUnitsRequired,
              generatorStakingAmount.toFixed(0),
              generatorData,
            );

          const extraStash = "112987298347983";
          await mockToken.connect(tokenHolder).approve(await generatorRegistry.getAddress(), extraStash);

          await expect(generatorRegistry.connect(tokenHolder).stake(await generator.getAddress(), extraStash))
            .to.emit(generatorRegistry, "AddedStake")
            .withArgs(await generator.getAddress(), extraStash)
            .to.emit(mockToken, "Transfer")
            .withArgs(await tokenHolder.getAddress(), await generatorRegistry.getAddress(), extraStash);
        });

        it("unstake should fail without request", async () => {
          await expect(generatorRegistry.connect(generator).unstake(await generator.getAddress())).to.be.revertedWith(
            await errorLibrary.UNSTAKE_REQUEST_NOT_IN_PLACE(),
          );
        });

        it("Decrease Compute should fail without request", async () => {
          await expect(generatorRegistry.connect(generator).decreaseDeclaredCompute()).to.be.revertedWith(
            await errorLibrary.REDUCE_COMPUTE_REQUEST_NOT_IN_PLACE(),
          );
        });

        describe("Request to Decrease Stake", () => {
          const newUtilization = exponent.dividedBy(10);
          beforeEach(async () => {
            await expect(generatorRegistry.connect(generator).intendToReduceStake(newUtilization.toFixed()))
              .to.emit(generatorRegistry, "RequestStakeDecrease")
              .withArgs(await generator.getAddress(), newUtilization.toFixed(0));
          });

          it("Generator utilization check and unstake", async () => {
            const generatorData = await generatorRegistry.generatorRegistry(await generator.getAddress());
            expect(generatorData.intendedStakeUtilization).to.eq(newUtilization);

            const totalStakeBefore = generatorData.totalStake;
            const expectedStakeAfter = new BigNumber(totalStakeBefore.toString())
              .multipliedBy(newUtilization)
              .div(exponent);
            const expectedAmountRelease = new BigNumber(totalStakeBefore.toString())
              .minus(expectedStakeAfter)
              .toFixed(0);

            await expect(generatorRegistry.connect(generator).unstake(await generator.getAddress()))
              .to.emit(generatorRegistry, "RemovedStake")
              .withArgs(await generator.getAddress(), expectedAmountRelease)
              .to.emit(mockToken, "Transfer")
              .withArgs(await generatorRegistry.getAddress(), await generator.getAddress(), expectedAmountRelease);
          });

          it("Should fail if unstake is called more than once per request", async () => {
            await generatorRegistry.connect(generator).unstake(await generator.getAddress());
            await expect(generatorRegistry.connect(generator).unstake(await generator.getAddress())).to.be.revertedWith(
              await errorLibrary.UNSTAKE_REQUEST_NOT_IN_PLACE(),
            );
          });
        });

        describe("Request to reduce compute", () => {
          const newUtilization = exponent.dividedBy(10);
          beforeEach(async () => {
            await expect(generatorRegistry.connect(generator).intendToReduceCompute(newUtilization.toFixed()))
              .to.emit(generatorRegistry, "RequestComputeDecrease")
              .withArgs(await generator.getAddress(), newUtilization.toFixed(0));
          });

          it("Generator utilization check and reduce compute", async () => {
            const generatorData = await generatorRegistry.generatorRegistry(await generator.getAddress());
            expect(generatorData.intendedComputeUtilization).to.eq(newUtilization);

            const totalComputeBefore = generatorData.declaredCompute;
            const expectedComputeAfter = new BigNumber(totalComputeBefore.toString())
              .multipliedBy(newUtilization)
              .div(exponent);
            const expectedComputeToRelease = new BigNumber(totalComputeBefore.toString())
              .minus(expectedComputeAfter)
              .toFixed(0);

            await expect(generatorRegistry.connect(generator).decreaseDeclaredCompute())
              .to.emit(generatorRegistry, "DecreaseCompute")
              .withArgs(await generator.getAddress(), expectedComputeToRelease);
          });

          it("Should fail if decrease compute is called more than once per request", async () => {
            await generatorRegistry.connect(generator).decreaseDeclaredCompute();
            await expect(generatorRegistry.connect(generator).decreaseDeclaredCompute()).to.be.revertedWith(
              await errorLibrary.REDUCE_COMPUTE_REQUEST_NOT_IN_PLACE(),
            );
          });
        });
      });

      describe("Task", () => {
        let proverBytes: string;
        let latestBlock: number;

        let askId: BigNumber;
        beforeEach(async () => {
          proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          const platformFee = new BigNumber((await proofMarketplace.costPerInputBytes(1)).toString()).multipliedBy(
            (proverBytes.length - 2) / 2,
          );

          latestBlock = await ethers.provider.getBlockNumber();

          let meAttestationBytes = await matchingEngineEnclave.getVerifiedAttestation(matchingEngineEnclave);

          let types = ["bytes", "address"];
          let values = [meAttestationBytes, await proofMarketplace.getAddress()];

          let abicode = new ethers.AbiCoder();
          let encoded = abicode.encode(types, values);
          let digest = ethers.keccak256(encoded);
          let signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

          await proofMarketplace.connect(admin).setMatchingEngineImage(matchingEngineEnclave.getPcrRlp());
          await proofMarketplace.connect(admin).verifyMatchingEngine(meAttestationBytes, signature);

          askId = new BigNumber((await proofMarketplace.askCounter()).toString());

          await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
          await proofMarketplace.connect(prover).createAsk(
            {
              marketId,
              proverData: proverBytes,
              reward: reward.toFixed(),
              expiry: latestBlock + assignmentExpiry,
              timeTakenForProofGeneration,
              deadline: latestBlock + maxTimeForProofGeneration,
              refundAddress: await prover.getAddress(),
            },
            0,
            "0x",
            "0x",
          );

          await generatorRegistry
            .connect(generator)
            .register(
              await generator.getAddress(),
              computeUnitsRequired,
              generatorStakingAmount.toFixed(0),
              generatorData,
            );

          await generatorRegistry
            .connect(generator)
            .joinMarketplace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");
        });

        it("Matching engine assignment", async () => {
          await expect(
            proofMarketplace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x1234"),
          )
            .to.emit(proofMarketplace, "TaskCreated")
            .withArgs(askId, await generator.getAddress(), "0x1234");

          expect((await proofMarketplace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(
            1,
          );

          // but via function it should be 2
          const data = await generatorRegistry.getGeneratorState(await generator.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine should assign using relayers [multiple tasks]", async () => {
          const types = ["uint256[]", "address[]", "bytes[]"];

          const values = [[askId.toFixed(0)], [await generator.getAddress()], ["0x1234"]];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketplace
              .connect(someRandomRelayer)
              .relayBatchAssignTasks([askId.toString()], [await generator.getAddress()], ["0x1234"], signature),
          )
            .to.emit(proofMarketplace, "TaskCreated")
            .withArgs(askId, await generator.getAddress(), "0x1234");

          expect((await proofMarketplace.listOfAsk(askId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state).to.eq(
            1,
          );

          // but via function it should be 2
          const data = await generatorRegistry.getGeneratorState(await generator.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine can't assign more than vcpus", async () => {
          await proofMarketplace
            .connect(matchingEngineSigner)
            .assignTask(askId.toString(), await generator.getAddress(), "0x1234");

          let anotherAskId = new BigNumber((await proofMarketplace.askCounter()).toString());
          let anotherProverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          const platformFee = new BigNumber((await proofMarketplace.costPerInputBytes(1)).toString()).multipliedBy(
            (anotherProverBytes.length - 2) / 2,
          );

          await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());
          await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
          await proofMarketplace.connect(prover).createAsk(
            {
              marketId,
              proverData: anotherProverBytes,
              reward: reward.toFixed(),
              expiry: latestBlock + assignmentExpiry,
              timeTakenForProofGeneration,
              deadline: latestBlock + maxTimeForProofGeneration,
              refundAddress: await prover.getAddress(),
            },
            0,
            "0x",
            "0x",
          );

          await expect(
            proofMarketplace
              .connect(matchingEngineSigner)
              .assignTask(anotherAskId.toString(), await generator.getAddress(), "0x1234"),
          ).to.be.revertedWith(await errorLibrary.ASSIGN_ONLY_TO_IDLE_GENERATORS());
        });

        it("Should fail: Matching engine will not be able to assign task if ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(
            proofMarketplace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x"),
          ).to.be.rejectedWith(await errorLibrary.SHOULD_BE_IN_CREATE_STATE());
        });

        it("Can cancel ask once the ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(proofMarketplace.connect(admin).cancelAsk(askId.toString()))
            .to.emit(proofMarketplace, "AskCancelled")
            .withArgs(askId)
            .to.emit(mockToken, "Transfer")
            .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed());
        });

        describe("Submit Proof", () => {
          let proof: string;
          let newIvsEnclave: MockEnclave;

          beforeEach(async () => {
            newIvsEnclave = new MockEnclave(MockIVSPCRS);
            proof = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

            await proofMarketplace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x");

            // generator should register his ivs for invalid inputs
            await updateIvsKey(newIvsEnclave);
          });

          const updateIvsKey = async (ivsEnclave: MockEnclave) => {
            let types = ["address"];
            let values = [await generator.getAddress()];

            let abicode = new ethers.AbiCoder();
            let encoded = abicode.encode(types, values);
            let digest = ethers.keccak256(encoded);
            let signature = await ivsEnclave.signMessage(ethers.getBytes(digest));

            // use any enclave to get verfied attestation as mockAttesationVerifier is used here
            let generatorIvsAttestationBytes = await ivsEnclave.getVerifiedAttestation(ivsEnclave);
            await generatorRegistry.connect(generator).addIvsKey(marketId, generatorIvsAttestationBytes, signature);
          };

          it("submit proof", async () => {
            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await expect(proofMarketplace.submitProof(askId.toString(), proof))
              .to.emit(proofMarketplace, "ProofCreated")
              .withArgs(askId, proof)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketplace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
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

            await expect(proofMarketplace.submitProofs([askId.toString()], [proof]))
              .to.emit(proofMarketplace, "ProofCreated")
              .withArgs(askId, proof)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketplace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect(
              (await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state,
            ).to.eq(1); // 1 means JOINED and idle now
          });

          it("Submit Proof for invalid request: using generator own ivs", async () => {
            const types = ["uint256"];

            const values = [askId.toFixed(0)];

            const abicode = new ethers.AbiCoder();
            const encoded = abicode.encode(types, values);
            const digest = ethers.keccak256(encoded);
            const signature = await newIvsEnclave.signMessage(ethers.getBytes(digest));

            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const treasuryRefundAddress = await treasury.getAddress();
            const expectedRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await proofMarketplace.flushToTreasury(); // remove anything if is already there

            await expect(proofMarketplace.submitProofForInvalidInputs(askId.toFixed(0), signature))
              .to.emit(proofMarketplace, "InvalidInputsDetected")
              .withArgs(askId)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), generatorAddress, expectedGeneratorReward);

            await expect(proofMarketplace.flushToTreasury())
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), treasuryRefundAddress, expectedRefund);
          });

          it("Submit Proof for invalid request, from another ivs enclave with same image id", async () => {
            const types = ["uint256"];

            const values = [askId.toFixed(0)];

            const abicode = new ethers.AbiCoder();
            const encoded = abicode.encode(types, values);
            const digest = ethers.keccak256(encoded);
            const anotherIvsEnclave = new MockEnclave(MockIVSPCRS);
            const signature = await anotherIvsEnclave.signMessage(ethers.getBytes(digest));

            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const treasuryRefundAddress = await treasury.getAddress();
            const expectedRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await proofMarketplace.flushToTreasury(); // remove anything if is already there

            // because enclave key for new enclave is not verified yet
            await expect(proofMarketplace.submitProofForInvalidInputs(askId.toFixed(0), signature)).to.be.revertedWith(
              await errorLibrary.INVALID_ENCLAVE_KEY(),
            );
            await updateIvsKey(anotherIvsEnclave);

            await expect(proofMarketplace.submitProofForInvalidInputs(askId.toFixed(0), signature))
              .to.emit(proofMarketplace, "InvalidInputsDetected")
              .withArgs(askId)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), generatorAddress, expectedGeneratorReward);

            await expect(proofMarketplace.flushToTreasury())
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), treasuryRefundAddress, expectedRefund);
          });

          it("Generator can ignore the request", async () => {
            await expect(proofMarketplace.connect(generator).discardRequest(askId.toString()))
              .to.emit(proofMarketplace, "ProofNotGenerated")
              .withArgs(askId)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed(0));
          });

          it("Can't slash request before deadline", async () => {
            await expect(
              proofMarketplace.connect(admin).slashGenerator(askId.toString(), await admin.getAddress()),
            ).to.be.revertedWith(await errorLibrary.SHOULD_BE_IN_CROSSED_DEADLINE_STATE());
          });

          describe("Failed submiited proof", () => {
            let slasher: Signer;

            beforeEach(async () => {
              slasher = signers[19];
              await mine(maxTimeForProofGeneration);
            });

            it("State should be deadline crossed", async () => {
              expect(await proofMarketplace.getAskState(askId.toString())).to.eq(5); // 5 means deadline crossed
            });

            it("When deadline is crossed, it is slashable", async () => {
              await expect(proofMarketplace.connect(admin).slashGenerator(askId.toString(), await admin.getAddress()))
                .to.emit(proofMarketplace, "ProofNotGenerated")
                .withArgs(askId)
                .to.emit(mockToken, "Transfer")
                .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed(0));
            });
          });
        });
      });
    });
  });
});
