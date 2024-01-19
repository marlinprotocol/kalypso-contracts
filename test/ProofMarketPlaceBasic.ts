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
  EntityKeyRegistry__factory,
} from "../typechain-types";

import {
  NO_ENCLAVE_ID,
  bytesToHexString,
  generateRandomBytes,
  generateWalletInfo,
  getMockUnverifiedAttestation,
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
  let platformToken: MockToken;

  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);

  let generatorStakingAmount = new BigNumber(10).pow(21).multipliedBy(6);

  let minRewardForGenerator = new BigNumber(10).pow(18).multipliedBy(100);

  let proofMarketPlace: ProofMarketPlace;
  let generatorRegistry: GeneratorRegistry;
  let mockVerifier: MockVerifier;

  let errorLibrary: Error;

  const exponent = new BigNumber(10).pow(18);

  const matchingEngineInternalWallet = generateWalletInfo();
  const ivsInternalWallet = generateWalletInfo();

  let matchingEngineSigner: Signer;
  let ivsSigner: Signer;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[1];
    tokenHolder = signers[2];
    treasury = signers[3];
    marketCreator = signers[4];

    matchingEngineSigner = new ethers.Wallet(matchingEngineInternalWallet.privateKey, admin.provider);
    ivsSigner = new ethers.Wallet(ivsInternalWallet.privateKey, admin.provider);
    await admin.sendTransaction({ to: matchingEngineInternalWallet.address, value: "1000000000000000000" });

    errorLibrary = await new Error__factory(admin).deploy();

    mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    platformToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    mockVerifier = await new MockVerifier__factory(admin).deploy();

    const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
    const entityRegistry = await new EntityKeyRegistry__factory(admin).deploy(
      await mockAttestationVerifier.getAddress(),
      await admin.getAddress(),
    );

    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [await mockToken.getAddress(), await entityRegistry.getAddress()],
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
        await mockAttestationVerifier.getAddress(),
      ],
    });
    proofMarketPlace = ProofMarketPlace__factory.connect(await proxy.getAddress(), signers[0]);

    await generatorRegistry.initialize(await admin.getAddress(), await proofMarketPlace.getAddress());

    expect(ethers.isAddress(await proofMarketPlace.getAddress())).is.true;
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

    await entityRegistry
      .connect(admin)
      .grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proofMarketPlace.getAddress());
  });

  it("Create Market", async () => {
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    const marketId = new BigNumber((await proofMarketPlace.marketCounter()).toString()).toFixed();

    await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());

    let abiCoder = new ethers.AbiCoder();

    const ivsPubkey = ivsInternalWallet.uncompressedPublicKey;

    let ivsAttestationBytes = abiCoder.encode(
      ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
      ["0x00", await admin.getAddress(), ivsPubkey, "0x00", "0x00", "0x00", "0x00", "0x00"],
    );

    let types = ["address"];
    let values = [await marketCreator.getAddress()];
    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await ivsSigner.signMessage(ethers.getBytes(digest));

    await expect(
      proofMarketPlace
        .connect(marketCreator)
        .createMarketPlace(
          marketBytes,
          await mockVerifier.getAddress(),
          exponent.div(100).toFixed(0),
          NO_ENCLAVE_ID,
          ivsAttestationBytes,
          Buffer.from("ivs url", "ascii"),
          signature,
        ),
    )
      .to.emit(proofMarketPlace, "MarketPlaceCreated")
      .withArgs(marketId);

    expect(await proofMarketPlace.verifier(marketId)).to.eq(await mockVerifier.getAddress());
  });

  it("Update Marketplace address", async () => {
    let abiCoder = new ethers.AbiCoder();

    const mePubKey = matchingEngineInternalWallet.uncompressedPublicKey;
    let inputBytes = abiCoder.encode(
      ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
      ["0x00", await admin.getAddress(), mePubKey, "0x00", "0x00", "0x00", "0x00", "0x00"],
    );
    let types = ["address"];

    let values = [await proofMarketPlace.getAddress()];

    let abicode = new ethers.AbiCoder();
    let encoded = abicode.encode(types, values);
    let digest = ethers.keccak256(encoded);
    let signature = await matchingEngineSigner.signMessage(ethers.getBytes(digest));

    await proofMarketPlace.connect(admin).updateMatchingEngineEncryptionKeyAndSigner(inputBytes, signature);

    expect(
      await proofMarketPlace.hasRole(
        await proofMarketPlace.MATCHING_ENGINE_ROLE(),
        matchingEngineInternalWallet.address,
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

      marketId = new BigNumber((await proofMarketPlace.marketCounter()).toString()).toFixed();

      await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed());

      let abiCoder = new ethers.AbiCoder();

      const ivsKey = ivsInternalWallet.uncompressedPublicKey;
      let ivsAttestationBytes = abiCoder.encode(
        ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
        ["0x00", await admin.getAddress(), ivsKey, "0x00", "0x00", "0x00", "0x00", "0x00"],
      );

      let types = ["address"];
      let values = [await marketCreator.getAddress()];
      let abicode = new ethers.AbiCoder();
      let encoded = abicode.encode(types, values);
      let digest = ethers.keccak256(encoded);
      let signature = await ivsSigner.signMessage(ethers.getBytes(digest));

      await proofMarketPlace
        .connect(marketCreator)
        .createMarketPlace(
          marketBytes,
          await mockVerifier.getAddress(),
          exponent.div(100).toFixed(0),
          NO_ENCLAVE_ID,
          ivsAttestationBytes,
          Buffer.from("test ivs url", "ascii"),
          signature,
        );

      let marketActivationDelay = await proofMarketPlace.MARKET_ACTIVATION_DELAY();
      await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
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

      await proofMarketPlace.grantRole(await proofMarketPlace.UPDATER_ROLE(), await admin.getAddress());
      await proofMarketPlace.connect(admin).updateCostPerBytes(1, 1000);

      const platformFee = await proofMarketPlace.getPlatformFee(1, askRequest, secretInfo, aclInfo);
      await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee);
      await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee);

      await expect(proofMarketPlace.connect(prover).createAsk(askRequest, 1, secretInfo, aclInfo))
        .to.emit(proofMarketPlace, "AskCreated")
        .withArgs(askIdToBeGenerated, true, "0x2345", "0x21")
        .to.emit(mockToken, "Transfer")
        .withArgs(await prover.getAddress(), await proofMarketPlace.getAddress(), reward)
        .to.emit(platformToken, "Transfer")
        .withArgs(await prover.getAddress(), await treasury.getAddress(), platformFee);

      expect((await proofMarketPlace.listOfAsk(askIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    it("Should Fail: when try creating market in invalid market", async () => {
      await mockToken.connect(prover).approve(await proofMarketPlace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes(1)).toString()).multipliedBy(
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

        await expect(
          generatorRegistry
            .connect(generator)
            .joinMarketPlace(
              marketId,
              computeUnitsRequired,
              minRewardForGenerator.toFixed(),
              100,
              false,
              getMockUnverifiedAttestation(await generator.getAddress()),
              "0x",
            ),
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
          .register(
            await generator.getAddress(),
            computeUnitsRequired,
            generatorStakingAmount.toFixed(0),
            generatorData,
          );

        await generatorRegistry
          .connect(generator)
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).leaveMarketPlace(marketId))
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
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

        await expect(generatorRegistry.connect(generator).leaveMarketPlaces([marketId]))
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
          .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");

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
          const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes(1)).toString()).multipliedBy(
            (proverBytes.length - 2) / 2,
          );
          await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
          await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());

          latestBlock = await ethers.provider.getBlockNumber();

          let abiCoder = new ethers.AbiCoder();

          const mePubKey = matchingEngineInternalWallet.uncompressedPublicKey;

          let inputBytes = abiCoder.encode(
            ["bytes", "address", "bytes", "bytes", "bytes", "bytes", "uint256", "uint256"],
            ["0x00", await admin.getAddress(), mePubKey, "0x00", "0x00", "0x00", "0x00", "0x00"],
          );

          let types = ["address"];

          let values = [await proofMarketPlace.getAddress()];

          let abicode = new ethers.AbiCoder();
          let encoded = abicode.encode(types, values);
          let digest = ethers.keccak256(encoded);
          let signature = await matchingEngineSigner.signMessage(ethers.getBytes(digest));
          await proofMarketPlace.connect(admin).updateMatchingEngineEncryptionKeyAndSigner(inputBytes, signature);

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
            .joinMarketPlace(marketId, computeUnitsRequired, minRewardForGenerator.toFixed(), 100, false, "0x", "0x");
        });

        it("Matching engine assings", async () => {
          await expect(
            proofMarketPlace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x1234"),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, await generator.getAddress(), "0x1234");

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
          const types = ["uint256", "address", "bytes"];

          const values = [askId.toFixed(0), await generator.getAddress(), "0x1234"];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await matchingEngineSigner.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketPlace
              .connect(someRandomRelayer)
              .relayAssignTask(askId.toString(), await generator.getAddress(), "0x1234", signature),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, await generator.getAddress(), "0x1234");

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
          const types = ["uint256[]", "address[]", "bytes[]"];

          const values = [[askId.toFixed(0)], [await generator.getAddress()], ["0x1234"]];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await matchingEngineSigner.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketPlace
              .connect(someRandomRelayer)
              .relayBatchAssignTasks([askId.toString()], [await generator.getAddress()], ["0x1234"], signature),
          )
            .to.emit(proofMarketPlace, "TaskCreated")
            .withArgs(askId, await generator.getAddress(), "0x1234");

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
          await proofMarketPlace
            .connect(matchingEngineSigner)
            .assignTask(askId.toString(), await generator.getAddress(), "0x1234");

          let anotherAskId = new BigNumber((await proofMarketPlace.askCounter()).toString());
          let anotherProverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes(1)).toString()).multipliedBy(
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
            0,
            "0x",
            "0x",
          );

          await expect(
            proofMarketPlace
              .connect(matchingEngineSigner)
              .assignTask(anotherAskId.toString(), await generator.getAddress(), "0x1234"),
          ).to.be.revertedWith(await errorLibrary.ASSIGN_ONLY_TO_IDLE_GENERATORS());
        });

        it("Should fail: Matching engine will not be able to assign task if ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(
            proofMarketPlace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x"),
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

          beforeEach(async () => {
            proof = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

            await proofMarketPlace
              .connect(matchingEngineSigner)
              .assignTask(askId.toString(), await generator.getAddress(), "0x");
          });

          it("submit proof", async () => {
            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await expect(proofMarketPlace.submitProof(askId.toString(), proof))
              .to.emit(proofMarketPlace, "ProofCreated")
              .withArgs(askId, proof)
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

            await expect(proofMarketPlace.submitProofs([askId.toString()], [proof]))
              .to.emit(proofMarketPlace, "ProofCreated")
              .withArgs(askId, proof)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketPlace.listOfAsk(askId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect(
              (await generatorRegistry.generatorInfoPerMarket(await generator.getAddress(), marketId)).state,
            ).to.eq(1); // 1 means JOINED and idle now
          });

          it("Submit Proof for invalid request", async () => {
            const types = ["uint256"];

            const values = [askId.toFixed(0)];

            const abicode = new ethers.AbiCoder();
            const encoded = abicode.encode(types, values);
            const digest = ethers.keccak256(encoded);
            const signature = await ivsSigner.signMessage(ethers.getBytes(digest));

            const generatorAddress = await generator.getAddress();
            const expectedGeneratorReward = (await generatorRegistry.generatorInfoPerMarket(generatorAddress, marketId))
              .proofGenerationCost;
            const treasuryRefundAddress = await treasury.getAddress();
            const expectedRefund = new BigNumber(reward).minus(expectedGeneratorReward.toString());

            await expect(proofMarketPlace.submitProofForInvalidInputs(askId.toFixed(0), signature))
              .to.emit(proofMarketPlace, "InvalidInputsDetected")
              .withArgs(askId)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), generatorAddress, expectedGeneratorReward)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), treasuryRefundAddress, expectedRefund);
          });

          it("Generator can ignore the request", async () => {
            await expect(proofMarketPlace.connect(generator).discardRequest(askId.toString()))
              .to.emit(proofMarketPlace, "ProofNotGenerated")
              .withArgs(askId)
              .to.emit(mockToken, "Transfer")
              .withArgs(await proofMarketPlace.getAddress(), await prover.getAddress(), reward.toFixed(0));
          });

          it("Can't slash request before deadline", async () => {
            await expect(
              proofMarketPlace.connect(admin).slashGenerator(askId.toString(), await admin.getAddress()),
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
              await expect(proofMarketPlace.connect(admin).slashGenerator(askId.toString(), await admin.getAddress()))
                .to.emit(proofMarketPlace, "ProofNotGenerated")
                .withArgs(askId)
                .to.emit(mockToken, "Transfer")
                .withArgs(await proofMarketPlace.getAddress(), await prover.getAddress(), reward.toFixed(0));
            });
          });
        });
      });
    });
  });
});
