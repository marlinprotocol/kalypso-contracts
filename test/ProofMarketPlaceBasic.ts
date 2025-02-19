import { BigNumber } from "bignumber.js";
import { expect } from "chai";
import { Signer } from "ethers";
import {
  ethers,
  upgrades,
} from "hardhat";

import { mine } from "@nomicfoundation/hardhat-network-helpers";

import {
  BridgeEnclavePCRS,
  bytesToHexString,
  generateRandomBytes,
  GodEnclavePCRS,
  matchingEngineFamilyId,
  MockEnclave,
  MockIVSPCRS,
  MockMEPCRS,
  MockProverPCRS,
  skipBlocks,
} from "../helpers";
import {
  Dispute__factory,
  EntityKeyRegistry,
  EntityKeyRegistry__factory,
  Error,
  Error__factory,
  MockAttestationVerifier__factory,
  MockToken,
  MockToken__factory,
  MockVerifier,
  MockVerifier__factory,
  ProofMarketplace,
  ProofMarketplace__factory,
  ProverManager,
  ProverManager__factory,
  StakingManager,
  StakingManager__factory,
  SymbioticStaking,
  SymbioticStaking__factory,
  SymbioticStakingReward,
  SymbioticStakingReward__factory,
} from "../typechain-types";

describe("Proof market place", () => {
  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let marketCreator: Signer;
  let mockToken: MockToken;

  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);
  let proverStakingAmount = new BigNumber(10).pow(21).multipliedBy(6);
  let minRewardForProver = new BigNumber(10).pow(18).multipliedBy(100);

  let stakingManager: StakingManager;
  let symbioticStaking: SymbioticStaking;
  let symbioticStakingReward: SymbioticStakingReward;
  let proofMarketplace: ProofMarketplace;
  let proverManager: ProverManager;
  let entityRegistry: EntityKeyRegistry;
  let mockVerifier: MockVerifier;

  let errorLibrary: Error;

  const exponent = new BigNumber(10).pow(18);
  const penaltyForNotComputingProof = exponent.div(100).toFixed(0);

  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const bridgeEnclave = new MockEnclave(BridgeEnclavePCRS);
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

    mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed(), "Payment Token", "PT");
    mockVerifier = await new MockVerifier__factory(admin).deploy();

    const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
    const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
    const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
      kind: "uups",
      constructorArgs: [await mockAttestationVerifier.getAddress()],
    });
    entityRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

    const StakingManager = await ethers.getContractFactory("StakingManager");
    const _stakingManager = await upgrades.deployProxy(StakingManager, [], {
      kind: "uups",
      initializer: false,
    });
    stakingManager = StakingManager__factory.connect(await _stakingManager.getAddress(), admin);

    const ProverManagerContract = await ethers.getContractFactory("ProverManager");
    const proverProxy = await upgrades.deployProxy(ProverManagerContract, [], {
      kind: "uups",
      initializer: false,
    });
    proverManager = ProverManager__factory.connect(await proverProxy.getAddress(), signers[0]);

    const SymbioticStaking = await ethers.getContractFactory("SymbioticStaking");
    const _symbioticStaking = await upgrades.deployProxy(SymbioticStaking, [], {
      kind: "uups",
      initializer: false,
    });
    symbioticStaking = SymbioticStaking__factory.connect(await _symbioticStaking.getAddress(), admin);

    const SymbioticStakingReward = await ethers.getContractFactory("SymbioticStakingReward");
    const _symbioticStakingReward = await upgrades.deployProxy(SymbioticStakingReward, [], {
      kind: "uups",
      initializer: false,
    });
    symbioticStakingReward = SymbioticStakingReward__factory.connect(await _symbioticStakingReward.getAddress(), admin);

    const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
    const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
      kind: "uups",
      constructorArgs: [],
      initializer: false,
    });

    proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), signers[0]);

    const dispute = await new Dispute__factory(admin).deploy(await entityRegistry.getAddress());

    await stakingManager.initialize(
      await admin.getAddress(),
      await proofMarketplace.getAddress(),
      await proverManager.getAddress(),
      await symbioticStaking.getAddress(),
      await mockToken.getAddress(),
    );
    await stakingManager.grantRole(await stakingManager.PROVER_MANAGER_ROLE(), await proverManager.getAddress());
    await symbioticStaking.initialize(
      await admin.getAddress(),
      await mockAttestationVerifier.getAddress(),
      await proofMarketplace.getAddress(),
      await stakingManager.getAddress(),
      await symbioticStakingReward.getAddress(),
    );
    await symbioticStakingReward.initialize(
      await admin.getAddress(),
      await proofMarketplace.getAddress(),
      await symbioticStaking.getAddress(),
      await mockToken.getAddress(),
    );
    await proverManager.initialize(
      await admin.getAddress(),
      await proofMarketplace.getAddress(),
      await stakingManager.getAddress(),
      await entityRegistry.getAddress(),
    );
    await proofMarketplace.initialize(
      await admin.getAddress(),
      await mockToken.getAddress(),
      await treasury.getAddress(),
      await proverManager.getAddress(),
      await entityRegistry.getAddress(),
      marketCreationCost.toFixed(),
    );

    expect(ethers.isAddress(await proofMarketplace.getAddress())).is.true;
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

    await entityRegistry.connect(admin).grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proofMarketplace.getAddress());

    await entityRegistry.connect(admin).grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proverManager.getAddress());

    await proofMarketplace.connect(admin).grantRole(await proofMarketplace.UPDATER_ROLE(), await admin.getAddress());
    await proofMarketplace.connect(admin).grantRole(await proofMarketplace.SYMBIOTIC_STAKING_ROLE(), await symbioticStaking.getAddress());
    await proofMarketplace
      .connect(admin)
      .grantRole(await proofMarketplace.SYMBIOTIC_STAKING_REWARD_ROLE(), await symbioticStakingReward.getAddress());
  });

  it("Create Market", async () => {
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    const marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

    await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

    const mockProver = new MockEnclave(MockProverPCRS);

    const tx = proofMarketplace
      .connect(marketCreator)
      .createMarket(
        marketBytes,
        await mockVerifier.getAddress(),
        mockProver.getPcrRlp(),
        ivsEnclave.getPcrRlp(),
      );

    await expect(tx)
      .to.emit(proofMarketplace, "MarketplaceCreated")
      .withArgs(marketId)
      .to.emit(entityRegistry, "EnclaveImageWhitelisted")
      .withArgs(mockProver.getImageId(), ...mockProver.pcrs)
      .to.emit(entityRegistry, "EnclaveImageWhitelisted")
      .withArgs(ivsEnclave.getImageId(), ...ivsEnclave.pcrs);

    expect((await proofMarketplace.marketData(marketId)).verifier).to.eq(await mockVerifier.getAddress());
  });

  describe("Public Market", () => {
    let marketBytes: string;
    let marketId: string;
    let mockProver: MockEnclave;
    beforeEach(async () => {
      marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB
      marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();
      await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());
      mockProver = new MockEnclave(); // pcrs will be 00

      const tx = proofMarketplace
        .connect(marketCreator)
        .createMarket(
          marketBytes,
          await mockVerifier.getAddress(),
          mockProver.getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        );

      await expect(tx)
        .to.emit(proofMarketplace, "MarketplaceCreated")
        .withArgs(marketId)
        .to.emit(entityRegistry, "EnclaveImageWhitelisted")
        .withArgs(ivsEnclave.getImageId(), ...ivsEnclave.pcrs);
    });

    it("Check: Create Public Marketion", async () => {
      expect((await proofMarketplace.marketData(marketId)).verifier).to.eq(await mockVerifier.getAddress());
    });

    it("cant add any provers to public markets as it is not an enclave", async () => {
      await expect(
        proofMarketplace.connect(marketCreator).addExtraImages(marketId, [mockProver.getPcrRlp()], []),
      ).to.revertedWithCustomError(proofMarketplace, "CannotModifyImagesForPublicMarkets");
    });

    it("IVS must be an enclave", async () => {
      await expect(
        proofMarketplace.connect(marketCreator).addExtraImages(marketId, [], [mockProver.getPcrRlp()]),
      ).to.revertedWithCustomError(entityRegistry, "MustBeAnEnclave");
    });
  });

  it("Should Fail: Create Market With non enclave IVS:", async () => {
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

    const mockProver = new MockEnclave(MockProverPCRS);
    const non_enclave_ivs = new MockEnclave();

    const tx = proofMarketplace
      .connect(marketCreator)
      .createMarket(
        marketBytes,
        await mockVerifier.getAddress(),
        mockProver.getPcrRlp(),
        non_enclave_ivs.getPcrRlp(),
      );

    await expect(tx).to.revertedWithCustomError(entityRegistry, "MustBeAnEnclave").withArgs(non_enclave_ivs.getImageId());
  });

  it("Can't create a marketplace if prover/ivs enclave is blacklisted", async () => {
    await entityRegistry.connect(admin).grantRole(await entityRegistry.MODERATOR_ROLE(), await admin.getAddress());

    await entityRegistry.connect(admin).blacklistImage(ivsEnclave.getImageId());
    const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

    await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

    const tempProver = new MockEnclave(MockProverPCRS);

    await expect(
      proofMarketplace
        .connect(marketCreator)
        .createMarket(
          marketBytes,
          await mockVerifier.getAddress(),
          tempProver.getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        ),
    )
      .to.be.revertedWithCustomError(entityRegistry, "BlacklistedImage")
      .withArgs(ivsEnclave.getImageId());

    await entityRegistry.connect(admin).blacklistImage(tempProver.getImageId());

    await expect(
      proofMarketplace
        .connect(marketCreator)
        .createMarket(
          marketBytes,
          await mockVerifier.getAddress(),
          tempProver.getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        ),
    )
      .to.be.revertedWithCustomError(entityRegistry, "BlacklistedImage")
      .withArgs(tempProver.getImageId());
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
      await entityRegistry.allowOnlyVerifiedFamily(
        matchingEngineFamilyId(await proofMarketplace.MATCHING_ENGINE_ROLE()),
        matchingEngineEnclave.getAddress(),
      ),
    ).to.not.be.reverted;
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
    await expect(proofMarketplace.connect(admin).verifyMatchingEngine(attestationBytes, signature)).to.be.revertedWithCustomError(
      entityRegistry,
      "AttestationAutherAttestationTooOld",
    );
  });

  describe("Ask: Private Market", () => {
    let prover: Signer;
    let reward = new BigNumber(10).pow(20).multipliedBy(3);
    let marketId: string;

    let assignmentExpiry = 100; // in blocks
    let timeForProofGeneration = 1000; // in blocks
    let maxTimeForProofGeneration = 10000; // in blocks

    beforeEach(async () => {
      prover = signers[5];
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

      marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

      await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

      await proofMarketplace
        .connect(marketCreator)
        .createMarket(
          marketBytes,
          await mockVerifier.getAddress(),
          new MockEnclave(MockProverPCRS).getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        );

      // let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
      // const ONE_DAY_IN_BLOCKS = 24 * 60 * 60;
      // await skipBlocks(ethers, ONE_DAY_IN_BLOCKS);
    });

    it("Create Ask Request", async () => {
      const latestBlock = await ethers.provider.getBlock("latest");
      const blockTimestamp = latestBlock?.timestamp ?? 0;

      const bidIdToBeGenerated = await proofMarketplace.bidCounter();

      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const askRequest = {
        marketId,
        proverData: proverBytes,
        reward: reward.toFixed(),
        expiry: (assignmentExpiry + blockTimestamp).toString(),
        timeForProofGeneration: timeForProofGeneration.toString(),
        deadline: (blockTimestamp + maxTimeForProofGeneration).toString(),
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

      await expect(proofMarketplace.connect(prover).createBid(askRequest, 1, secretInfo, aclInfo, "0x"))
        .to.emit(proofMarketplace, "BidCreated")
        .withArgs(bidIdToBeGenerated, true, "0x2345", "0x21", "0x")
        .to.emit(mockToken, "Transfer")
        .withArgs(await prover.getAddress(), await proofMarketplace.getAddress(), new BigNumber(platformFee.toString()).plus(reward));

      expect((await proofMarketplace.listOfBid(bidIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });
  });
  describe("Ask: Public Market", () => {
    let prover: Signer;
    let reward = new BigNumber(10).pow(20).multipliedBy(3);
    let marketId: string;

    let assignmentExpiry = 100; // in blocks
    let timeForProofGeneration = 1000; // in blocks
    let maxTimeForProofGeneration = 10000; // in blocks

    const computeUnitsRequired = 100; // temporary absolute number

    beforeEach(async () => {
      prover = signers[5];
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB

      marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

      await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

      await proofMarketplace.connect(marketCreator).createMarket(
        marketBytes,
        await mockVerifier.getAddress(),
        new MockEnclave().getPcrRlp(), // no pcrs means not enclave
        ivsEnclave.getPcrRlp(),
      );

      // let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
      // await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
    });

    it("Create Ask Request", async () => {
      const latestBlock = await ethers.provider.getBlock("latest");
      const blockTimestamp = latestBlock?.timestamp ?? 0;

      const bidIdToBeGenerated = await proofMarketplace.bidCounter();

      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
      const askRequest = {
        marketId,
        proverData: proverBytes,
        reward: reward.toFixed(),
        expiry: (assignmentExpiry + blockTimestamp).toString(),
        timeForProofGeneration: timeForProofGeneration.toString(),
        deadline: (blockTimestamp + maxTimeForProofGeneration).toString(),
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

      await expect(proofMarketplace.connect(prover).createBid(askRequest, 1, secretInfo, aclInfo, "0x"))
        .to.emit(proofMarketplace, "BidCreated")
        .withArgs(bidIdToBeGenerated, false, "0x", "0x", "0x")
        .to.emit(mockToken, "Transfer")
        .withArgs(await prover.getAddress(), await proofMarketplace.getAddress(), new BigNumber(platformFee.toString()).plus(reward));

      expect((await proofMarketplace.listOfBid(bidIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    it("Should Fail: when try creating market in invalid market", async () => {
      await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
      const proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

      const latestBlock = await ethers.provider.getBlock("latest");
      const blockTimestamp = latestBlock?.timestamp ?? 0;

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 2)); // 10 MB
      const invalidMarketId = ethers.keccak256(marketBytes);

      await expect(
        proofMarketplace.connect(prover).createBid(
          {
            marketId: invalidMarketId,
            proverData: proverBytes,
            reward: reward.toFixed(),
            expiry: (assignmentExpiry + blockTimestamp).toString(),
            timeForProofGeneration: timeForProofGeneration.toString(),
            deadline: (blockTimestamp + maxTimeForProofGeneration).toString(),
            refundAddress: await prover.getAddress(),
          },
          0,
          "0x",
          "0x",
          "0x",
          "0x",
        ),
      ).to.be.revertedWithPanic(0x32); // 0x32 mean array out of bounds // market is not created
    });

    describe("Prover", () => {
      let proverData: string;
      let prover: Signer;

      beforeEach(async () => {
        prover = await signers[12];
        proverData = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
        await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), proverStakingAmount.toFixed());

        // await mockToken.connect(prover).approve(await proverManager.getAddress(), proverStakingAmount.toFixed());
        // amount locked can be anything, it get overrides within the contract
      });

      it("Check prover data", async () => {
        await expect(proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData))
          .to.emit(proverManager, "ProverRegistered")
          .withArgs(await prover.getAddress(), computeUnitsRequired, proverData);

        let proverEnclave = new MockEnclave(MockProverPCRS);
        await expect(
          proverManager.connect(prover).joinMarketplace(
            marketId,
            computeUnitsRequired,
            minRewardForProver.toFixed(),
            100,
            new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
            false,
            await proverEnclave.getVerifiedAttestation(proverEnclave),
            "0x",
          ),
        )
          .to.emit(proverManager, "ProverJoinedMarketplace")
          .withArgs(await prover.getAddress(), marketId, computeUnitsRequired, new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0)); // 10%

        const rewardAddress = (await proverManager.proverRegistry(await prover.getAddress())).rewardAddress;
        expect(rewardAddress).to.eq(await prover.getAddress());

        expect((await proverManager.proverInfoPerMarket(await prover.getAddress(), marketId)).state).to.eq(1); //1 means JOINED
      });

      it("request for market place exit", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await proverManager.connect(prover).joinMarketplace(
          marketId,
          computeUnitsRequired,
          minRewardForProver.toFixed(),
          100,
          new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
          false,
          "0x",
          "0x",
        );

        await expect(proverManager.connect(prover).requestForExitMarketplace(marketId))
          .to.emit(proverManager, "ProverRequestedMarketplaceExit")
          .withArgs(await prover.getAddress(), marketId)
          .to.emit(proverManager, "ProverLeftMarketplace")
          .withArgs(await prover.getAddress(), marketId);
      });

      it("request for market place exit: array", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await proverManager.connect(prover).joinMarketplace(
          marketId,
          computeUnitsRequired,
          minRewardForProver.toFixed(),
          100,
          new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
          false,
          "0x",
          "0x",
        );

        await expect(proverManager.connect(prover).requestForExitMarketplaces([marketId]))
          .to.emit(proverManager, "ProverRequestedMarketplaceExit")
          .withArgs(await prover.getAddress(), marketId);
      });

      it("leave market place", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await proverManager.connect(prover).joinMarketplace(
          marketId,
          computeUnitsRequired,
          minRewardForProver.toFixed(),
          100,
          new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
          false,
          "0x",
          "0x",
        );

        await expect(proverManager.connect(prover).leaveMarketplace(marketId))
          .to.emit(proverManager, "ProverLeftMarketplace")
          .withArgs(await prover.getAddress(), marketId);
      });

      it("leave multiple markets", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await proverManager.connect(prover).joinMarketplace(
          marketId,
          computeUnitsRequired,
          minRewardForProver.toFixed(),
          100,
          new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
          false,
          "0x",
          "0x",
        );

        await expect(proverManager.connect(prover).leaveMarketplaces([marketId]))
          .to.emit(proverManager, "ProverLeftMarketplace")
          .withArgs(await prover.getAddress(), marketId);
      });

      it("Can't de-register if prover is active part of proof market", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await proverManager.connect(prover).joinMarketplace(
          marketId,
          computeUnitsRequired,
          minRewardForProver.toFixed(),
          100,
          new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
          false,
          "0x",
          "0x",
        );

        await expect(proverManager.connect(prover).deregister()).to.be.revertedWithCustomError(
          errorLibrary,
          "CannotLeaveWithActiveMarket",
        );
      });

      it("Deregister prover data", async () => {
        await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

        await expect(proverManager.connect(prover).deregister())
          .to.emit(proverManager, "ProverDeregistered")
          .withArgs(await prover.getAddress());
      });

      // it("extra stash can be added to prover by anyone", async () => {
      //   await proverManager
      //     .connect(prover)
      //     .register(await prover.getAddress(), computeUnitsRequired, proverData);

      //   const extraStash = "112987298347983";
      //   await mockToken.connect(tokenHolder).approve(await proverManager.getAddress(), extraStash);

      //   await expect(proverManager.connect(tokenHolder).stake(await prover.getAddress(), extraStash))
      //     .to.emit(proverManager, "AddedStake")
      //     .withArgs(await prover.getAddress(), extraStash)
      //     .to.emit(mockToken, "Transfer")
      //     .withArgs(await tokenHolder.getAddress(), await proverManager.getAddress(), extraStash);
      // });

      describe("Prover After Staking", () => {
        const extraStash = "112987298347983";
        beforeEach(async () => {
          await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

          await mockToken.connect(tokenHolder).approve(await proverManager.getAddress(), extraStash);

          // await expect(proverManager.connect(tokenHolder).stake(await prover.getAddress(), extraStash))
          //   .to.emit(proverManager, "AddedStake")
          //   .withArgs(await prover.getAddress(), extraStash)
          //   .to.emit(mockToken, "Transfer")
          //   .withArgs(await tokenHolder.getAddress(), await proverManager.getAddress(), extraStash);
        });

        // it("unstake should fail without request", async () => {
        //   await expect(proverManager.connect(prover).unstake(await prover.getAddress())).to.be.revertedWithCustomError(
        //     errorLibrary,
        //     "UnstakeRequestNotInPlace",
        //   );
        // });

        it("Decrease Compute should fail without request", async () => {
          await expect(proverManager.connect(prover).decreaseDeclaredCompute()).to.be.revertedWithCustomError(
            errorLibrary,
            "ReduceComputeRequestNotInPlace",
          );
        });

        // describe("Request to Decrease Stake", () => {
        //   const updatedProverStakingAmount = proverStakingAmount.plus(extraStash);

        //   const stakeToReduce = updatedProverStakingAmount.multipliedBy(9).div(10);
        //   const expectedNewTotalStake = updatedProverStakingAmount.minus(stakeToReduce);
        //   const newUtilization = expectedNewTotalStake.multipliedBy(exponent).dividedBy(updatedProverStakingAmount).minus(1); // to offset the uint256 thing in solidity

        //   beforeEach(async () => {
        //     await expect(proverManager.connect(prover).intendToReduceStake(stakeToReduce.toFixed(0)))
        //       .to.emit(proverManager, "RequestStakeDecrease")
        //       .withArgs(await prover.getAddress(), newUtilization.toFixed(0));
        //   });

        //   it("Prover utilization check and unstake", async () => {
        //     const proverData = await proverManager.proverManager(await prover.getAddress());
        //     expect(proverData.intendedStakeUtilization).to.eq(newUtilization);

        //     const totalStakeBefore = proverData.totalStake;
        //     const expectedStakeAfter = new BigNumber(totalStakeBefore.toString()).multipliedBy(newUtilization).div(exponent);
        //     const expectedAmountRelease = new BigNumber(totalStakeBefore.toString()).minus(expectedStakeAfter).toFixed(0);

        //     await expect(proverManager.connect(prover).unstake(await prover.getAddress()))
        //       .to.emit(proverManager, "RemovedStake")
        //       .withArgs(await prover.getAddress(), expectedAmountRelease)
        //       .to.emit(mockToken, "Transfer")
        //       .withArgs(await proverManager.getAddress(), await prover.getAddress(), expectedAmountRelease);
        //   });

        //   it("Should fail if unstake is called more than once per request", async () => {
        //     await proverManager.connect(prover).unstake(await prover.getAddress());
        //     await expect(proverManager.connect(prover).unstake(await prover.getAddress())).to.be.revertedWithCustomError(
        //       errorLibrary,
        //       "UnstakeRequestNotInPlace",
        //     );
        //   });
        // });

        describe("Request to reduce compute", () => {
          const computeToReduce = new BigNumber(computeUnitsRequired).multipliedBy(9).div(10).toFixed(0);
          const newUtilization = exponent.dividedBy(10); // should be 10% of if compute is reduced by 90%
          beforeEach(async () => {
            await expect(proverManager.connect(prover).intendToReduceCompute(computeToReduce))
              .to.emit(proverManager, "ComputeDecreaseRequested")
              .withArgs(await prover.getAddress(), newUtilization.toFixed(0));
            
            await skipBlocks(ethers, 1000);
          });

          it("Prover utilization check and reduce compute", async () => {
            const proverData = await proverManager.proverRegistry(await prover.getAddress());
            expect(proverData.intendedComputeUtilization).to.eq(newUtilization);

            const totalComputeBefore = proverData.declaredCompute;
            const expectedComputeAfter = new BigNumber(totalComputeBefore.toString()).multipliedBy(newUtilization).div(exponent);
            const expectedComputeToRelease = new BigNumber(totalComputeBefore.toString()).minus(expectedComputeAfter).toFixed(0);

            await expect(proverManager.connect(prover).decreaseDeclaredCompute())
              .to.emit(proverManager, "ComputeDecreased")
              .withArgs(await prover.getAddress(), expectedComputeToRelease);
          });

          it("Should fail if decrease compute is called more than once per request", async () => {
            await proverManager.connect(prover).decreaseDeclaredCompute();
            await expect(proverManager.connect(prover).decreaseDeclaredCompute()).to.be.revertedWithCustomError(
              errorLibrary,
              "ReduceComputeRequestNotInPlace",
            );
          });
        });
      });

      describe("Task", () => {
        let proverBytes: string;
        let latestBlock: any;
        let blockTimestamp: number;
        let bidId: BigNumber;
        beforeEach(async () => {
          proverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB
          latestBlock = await ethers.provider.getBlock("latest");
          blockTimestamp = latestBlock?.timestamp ?? 0;
          
          let meAttestationBytes = await matchingEngineEnclave.getVerifiedAttestation(matchingEngineEnclave);

          let types = ["bytes", "address"];
          let values = [meAttestationBytes, await proofMarketplace.getAddress()];

          let abicode = new ethers.AbiCoder();
          let encoded = abicode.encode(types, values);
          let digest = ethers.keccak256(encoded);
          let signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

          await proofMarketplace.connect(admin).setMatchingEngineImage(matchingEngineEnclave.getPcrRlp());
          await proofMarketplace.connect(admin).verifyMatchingEngine(meAttestationBytes, signature);

          bidId = new BigNumber((await proofMarketplace.bidCounter()).toString());

          await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
          await proofMarketplace.connect(prover).createBid(
            {
              marketId,
              proverData: proverBytes,
              reward: reward.toFixed(),
              expiry: (blockTimestamp + assignmentExpiry).toString(),
              timeForProofGeneration: timeForProofGeneration.toString(),
              deadline: (blockTimestamp + maxTimeForProofGeneration).toString(),
              refundAddress: await prover.getAddress(),
            },
            0,
            "0x",
            "0x",
            "0x",
            "0x",
          );

          await proverManager.connect(prover).register(await prover.getAddress(), computeUnitsRequired, proverData);

          await proverManager.connect(prover).joinMarketplace(
            marketId,
            computeUnitsRequired,
            minRewardForProver.toFixed(),
            100,
            new BigNumber(10).pow(18).multipliedBy(0.1).toFixed(0), // 10%
            false,
            "0x",
            "0x",
          );
        });

        it("Can't discard request before assignment (by anyone)", async () => {
          await expect(proofMarketplace.connect(prover).discardRequest(bidId.toString()))
            .to.revertedWithCustomError(proofMarketplace, "ShouldBeInAssignedState")
            .withArgs(bidId);

          await expect(proofMarketplace.connect(treasury).discardRequest(bidId.toString()))
            .to.revertedWithCustomError(proofMarketplace, "ShouldBeInAssignedState")
            .withArgs(bidId);
        });

        it("Matching engine assignment", async () => {
          await expect(proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x1234"))
            .to.emit(proofMarketplace, "TaskCreated")
            .withArgs(bidId, await prover.getAddress(), "0x1234")
            .to.emit(proverManager, "ComputeLocked")
            .withArgs(await prover.getAddress(), computeUnitsRequired);

          expect((await proofMarketplace.listOfBid(bidId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await proverManager.proverInfoPerMarket(await prover.getAddress(), marketId)).state).to.eq(1);

          // but via function it should be 2
          const data = await proverManager.getProverState(await prover.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine should assign using relayers [multiple tasks]", async () => {
          const types = ["uint256[]", "address[]", "bytes[]"];

          const values = [[bidId.toFixed(0)], [await prover.getAddress()], ["0x1234"]];

          const abicode = new ethers.AbiCoder();
          const encoded = abicode.encode(types, values);
          const digest = ethers.keccak256(encoded);
          const signature = await matchingEngineEnclave.signMessage(ethers.getBytes(digest));

          const someRandomRelayer = admin;

          await expect(
            proofMarketplace
              .connect(someRandomRelayer)
              .relayBatchAssignTasks([bidId.toString()], [await prover.getAddress()], ["0x1234"], signature),
          )
            .to.emit(proofMarketplace, "TaskCreated")
            .withArgs(bidId, await prover.getAddress(), "0x1234");

          expect((await proofMarketplace.listOfBid(bidId.toString())).state).to.eq(3); // 3 means ASSIGNED

          // in store it will be 1
          expect((await proverManager.proverInfoPerMarket(await prover.getAddress(), marketId)).state).to.eq(1);

          // but via function it should be 2
          const data = await proverManager.getProverState(await prover.getAddress(), marketId);
          expect(data[0]).to.eq(2);
        });

        it("Matching Engine can't assign more than vcpus", async () => {
          await proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x1234");

          let anotherbidId = new BigNumber((await proofMarketplace.bidCounter()).toString());
          let anotherProverBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

          await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());
          await mockToken.connect(prover).approve(await proofMarketplace.getAddress(), reward.toFixed());
          await proofMarketplace.connect(prover).createBid(
            {
              marketId,
              proverData: anotherProverBytes,
              reward: reward.toFixed(),
              expiry: (blockTimestamp + assignmentExpiry).toString(),
              timeForProofGeneration: timeForProofGeneration.toString(),
              deadline: (blockTimestamp + maxTimeForProofGeneration).toString(),
              refundAddress: await prover.getAddress(),
            },
            0,
            "0x",
            "0x",
            "0x",
            "0x",
          );

          await expect(
            proofMarketplace.connect(matchingEngineSigner).assignTask(anotherbidId.toString(), await prover.getAddress(), "0x1234"),
          ).to.be.revertedWithCustomError(errorLibrary, "AssignOnlyToIdleProvers");
        });

        it("Should fail: Matching engine will not be able to assign task if ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(
            proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x"),
          ).to.be.revertedWithCustomError(errorLibrary, "ShouldBeInCreateState");
        });

        it("Can cancel ask once the ask is expired", async () => {
          await mine(assignmentExpiry);
          await expect(proofMarketplace.connect(admin).cancelBid(bidId.toString()))
            .to.emit(proofMarketplace, "BidCancelled")
            .withArgs(bidId);

          // await expect(proofMarketplace.flush(await prover.getAddress()))
          //   .to.emit(mockToken, "Transfer")
          //   .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed());
        });

        it("Matching can't assign task if it image is blacklisted by moderator", async () => {
          await entityRegistry.connect(admin).grantRole(await entityRegistry.MODERATOR_ROLE(), await admin.getAddress());
          await entityRegistry.connect(admin).blacklistImage(matchingEngineEnclave.getImageId());

          await expect(
            proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x"),
          ).to.be.revertedWithCustomError(entityRegistry, "AttestationAutherImageNotWhitelisted");
        });

        it("Matching can't assign task if it image is removed from family", async () => {
          await entityRegistry.connect(admin).grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await admin.getAddress());
          await entityRegistry
            .connect(admin)
            .removeEnclaveImageFromFamily(
              matchingEngineEnclave.getImageId(),
              matchingEngineFamilyId(await proofMarketplace.MATCHING_ENGINE_ROLE()),
            );

          await expect(
            proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x"),
          ).to.be.revertedWithCustomError(entityRegistry, "AttestationAutherImageNotInFamily");
        });

        describe("Submit Proof", () => {
          let proof: string;
          let newIvsEnclave: MockEnclave;

          beforeEach(async () => {
            newIvsEnclave = new MockEnclave(MockIVSPCRS);
            proof = "0x" + bytesToHexString(await generateRandomBytes(1024 * 1)); // 1 MB

            await proofMarketplace.connect(matchingEngineSigner).assignTask(bidId.toString(), await prover.getAddress(), "0x");

            // prover should register his ivs for invalid inputs
            await updateIvsKey(newIvsEnclave);
          });

          const updateIvsKey = async (ivsEnclave: MockEnclave) => {
            // use any enclave here as AV is mocked
            const noUseEnclave = new MockEnclave([MockIVSPCRS[2], MockProverPCRS[2], GodEnclavePCRS[2]]);
            let ivsAttestationBytes = await ivsEnclave.getVerifiedAttestation(noUseEnclave); // means ivs should get verified attestation from noUseEnclave

            let types = ["bytes", "address"];
            let values = [ivsAttestationBytes, await prover.getAddress()];

            let abicode = new ethers.AbiCoder();
            let encoded = abicode.encode(types, values);
            let digest = ethers.keccak256(encoded);
            let signature = await ivsEnclave.signMessage(ethers.getBytes(digest));

            // console.log("let ivs_attestation = \""+ivsAttestationBytes+"\";")
            // console.log("let expected_signature = \""+signature+"\";")
            // console.log("let recovery_address = \""+ivsEnclave.getAddress()+"\";")
            // console.log("let private_key = \""+ivsEnclave.getPrivateKey(true)+"\";")
            // console.log("let address_to_sign = \""+await prover.getAddress()+"\";")

            // use any enclave to get verfied attestation as mockAttesationVerifier is used here
            await expect(proverManager.connect(prover).addIvsKey(marketId, ivsAttestationBytes, signature))
              .to.emit(proverManager, "IvKeyAdded")
              .withArgs(marketId, ivsEnclave.getAddress());
          };

          it("submit proof", async () => {
            const proverAddress = await prover.getAddress();
            const expectedProverReward = (await proverManager.proverInfoPerMarket(proverAddress, marketId)).proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedProverReward.toString());

            await expect(proofMarketplace.submitProof(bidId.toString(), proof))
              .to.emit(proofMarketplace, "ProofCreated")
              .withArgs(bidId, proof)
              .to.emit(proverManager, "ComputeReleased")
              .withArgs(await prover.getAddress(), computeUnitsRequired);

            // await expect(proofMarketplace.flush(proverAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverAddress, expectedProverReward);

            // await expect(proofMarketplace.flush(proverRefundAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketplace.listOfBid(bidId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect((await proverManager.proverInfoPerMarket(await prover.getAddress(), marketId)).state).to.eq(1); // 1 means JOINED and idle now
          });

          it("Submit Proof via array", async () => {
            const proverAddress = await prover.getAddress();
            const expectedProverReward = (await proverManager.proverInfoPerMarket(proverAddress, marketId)).proofGenerationCost;
            const proverRefundAddress = await prover.getAddress();
            const expectedProverRefund = new BigNumber(reward).minus(expectedProverReward.toString());

            await expect(proofMarketplace.submitProofs([bidId.toString()], [proof]))
              .to.emit(proofMarketplace, "ProofCreated")
              .withArgs(bidId, proof);

            // await expect(proofMarketplace.flush(proverAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverAddress, expectedProverReward);

            // await expect(proofMarketplace.flush(proverRefundAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverRefundAddress, expectedProverRefund);

            expect((await proofMarketplace.listOfBid(bidId.toString())).state).to.eq(4); // 4 means COMPLETE
            expect((await proverManager.proverInfoPerMarket(await prover.getAddress(), marketId)).state).to.eq(1); // 1 means JOINED and idle now
          });

          it("Submit Proof for invalid request: using own ivs", async () => {
            const askData = await proofMarketplace.listOfBid(bidId.toFixed(0));
            const types = ["uint256", "bytes"];

            const values = [bidId.toFixed(0), askData.bid.proverData];

            const abicode = new ethers.AbiCoder();
            const encoded = abicode.encode(types, values);
            const digest = ethers.keccak256(encoded);
            const signature = await newIvsEnclave.signMessage(ethers.getBytes(digest));

            const proverAddress = await prover.getAddress();
            const expectedProverReward = (await proverManager.proverInfoPerMarket(proverAddress, marketId)).proofGenerationCost;
            const treasuryRefundAddress = await treasury.getAddress();
            const expectedRefund = new BigNumber(reward).minus(expectedProverReward.toString());

            // TODO
            // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

            await expect(proofMarketplace.submitProofForInvalidInputs(bidId.toFixed(0), signature))
              .to.emit(proofMarketplace, "InvalidInputsDetected")
              .withArgs(bidId);

            // await expect(proofMarketplace.flush(proverAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverAddress, expectedProverReward);

            // await expect(proofMarketplace.flush(await treasury.getAddress()))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), treasuryRefundAddress, expectedRefund);
          });

          it("Submit Proof for invalid request, from another ivs enclave with same image id", async () => {
            const askData = await proofMarketplace.listOfBid(bidId.toFixed(0));
            const types = ["uint256", "bytes"];

            const values = [bidId.toFixed(0), askData.bid.proverData];

            const abicode = new ethers.AbiCoder();
            const encoded = abicode.encode(types, values);
            const digest = ethers.keccak256(encoded);
            const anotherIvsEnclave = new MockEnclave(MockIVSPCRS);
            const signature = await anotherIvsEnclave.signMessage(ethers.getBytes(digest));

            const proverAddress = await prover.getAddress();
            const expectedProverReward = (await proverManager.proverInfoPerMarket(proverAddress, marketId)).proofGenerationCost;
            const treasuryRefundAddress = await treasury.getAddress();
            const expectedRefund = new BigNumber(reward).minus(expectedProverReward.toString());

            // TODO
            // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

            // because enclave key for new enclave is not verified yet
            await expect(proofMarketplace.submitProofForInvalidInputs(bidId.toFixed(0), signature)).to.be.revertedWithCustomError(
              entityRegistry,
              "AttestationAutherKeyNotVerified",
            );
            await updateIvsKey(anotherIvsEnclave);

            await expect(proofMarketplace.submitProofForInvalidInputs(bidId.toFixed(0), signature))
              .to.emit(proofMarketplace, "InvalidInputsDetected")
              .withArgs(bidId);

            // await expect(proofMarketplace.flush(proverAddress))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), proverAddress, expectedProverReward);

            // await expect(proofMarketplace.flush(await treasury.getAddress()))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), treasuryRefundAddress, expectedRefund);
          });

          it("Prover can ignore the request", async () => {
            await expect(proofMarketplace.connect(prover).discardRequest(bidId.toString()))
              .to.emit(proofMarketplace, "ProofNotGenerated")
              .withArgs(bidId);
            // await expect(proofMarketplace.flush(await prover.getAddress()))
            //   .to.emit(mockToken, "Transfer")
            //   .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed(0));
          });

          it("Should Fail: No one other than prover discard his own request", async () => {
            await expect(proofMarketplace.connect(treasury).discardRequest(bidId.toString()))
              .to.revertedWithCustomError(proofMarketplace, "OnlyProverCanDiscardRequest")
              .withArgs(bidId);
          });

          // it("Can't slash request before deadline", async () => {
          //   await expect(
          //     proofMarketplace.connect(admin).slashProver(bidId.toString(), await admin.getAddress()),
          //   ).to.be.revertedWithCustomError(errorLibrary, "DeadlineNotCrossed");
          // });

          describe("Failed submiited proof", () => {
            let slasher: Signer;

            beforeEach(async () => {
              slasher = signers[19];
              await mine(maxTimeForProofGeneration);
            });

            it("State should be deadline crossed", async () => {
              expect(await proofMarketplace.getBidState(bidId.toString())).to.eq(5); // 5 means deadline crossed
            });

            it("Prover can't discard request when deadline crossed", async () => {
              await expect(proofMarketplace.connect(prover).discardRequest(bidId.toString()))
                .to.revertedWithCustomError(proofMarketplace, "ShouldBeInAssignedState")
                .withArgs(bidId);
            });

            // it("When deadline is crossed, it is slashable by anyone", async () => {
            //   await expect(proofMarketplace.connect(admin).slashProver(bidId.toString(), await admin.getAddress()))
            //     .to.emit(proofMarketplace, "ProofNotGenerated")
            //     .withArgs(bidId);

            //   await expect(proofMarketplace.flush(await prover.getAddress()))
            //     .to.emit(mockToken, "Transfer")
            //     .withArgs(await proofMarketplace.getAddress(), await prover.getAddress(), reward.toFixed(0));
            // });

            it("Should fail: Submit proof after deadline", async () => {
              await expect(proofMarketplace.submitProofs([bidId.toString()], [proof]))
                .to.revertedWithCustomError(proofMarketplace, "OnlyAssignedBidsCanBeProved")
                .withArgs(bidId);
            });
          });
        });
      });
    });
  });
});
