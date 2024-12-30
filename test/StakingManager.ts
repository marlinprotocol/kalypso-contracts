import BigNumber from 'bignumber.js';
import { expect } from 'chai';
import { Signer } from 'ethers';
import {
  ethers,
  upgrades,
} from 'hardhat';

import {
  bytesToHexString,
  generateRandomBytes,
  MockEnclave,
  MockIVSPCRS,
  MockMEPCRS,
  MockProverPCRS,
  skipBlocks,
} from '../helpers';
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
  NativeStaking,
  NativeStaking__factory,
  ProofMarketplace,
  ProofMarketplace__factory,
  ProverRegistry,
  ProverRegistry__factory,
  StakingManager,
  StakingManager__factory,
  SymbioticStaking,
  SymbioticStaking__factory,
  SymbioticStakingReward,
  SymbioticStakingReward__factory,
} from '../typechain-types';

describe("Staking manager", () => {
  /* Signers */
  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let marketCreator: Signer;
  let matchingEngineSigner: Signer;

  /* Constants */
  const tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4); // 4 * 10^24
  const marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5); // 5 * 10^20
  const proverStakingAmount = new BigNumber(10).pow(21).multipliedBy(6); // 6 * 10^21
  const minRewardForProver = new BigNumber(10).pow(18).multipliedBy(100); // 100 * 10^18
  const exponent = new BigNumber(10).pow(18);
  const penaltyForNotComputingProof = exponent.div(100).toFixed(0);

  /* Contracts */
  let mockToken: MockToken;
  let stakingManager: StakingManager;
  let nativeStaking: NativeStaking;
  let symbioticStaking: SymbioticStaking;
  let symbioticStakingReward: SymbioticStakingReward;
  let proofMarketplace: ProofMarketplace;
  let proverRegistry: ProverRegistry;
  let entityRegistry: EntityKeyRegistry;
  let mockVerifier: MockVerifier;
  let errorLibrary: Error;

  /* Enclaves */
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const ivsEnclave = new MockEnclave(MockIVSPCRS);

  describe("Staking Manager", () => {
    beforeEach(async () => {
      // Setup signers
      signers = await ethers.getSigners();
      admin = signers[1];
      tokenHolder = signers[2];
      treasury = signers[3];
      marketCreator = signers[4];
      matchingEngineSigner = new ethers.Wallet(matchingEngineEnclave.getPrivateKey(true), admin.provider);
      await admin.sendTransaction({ to: matchingEngineEnclave.getAddress(), value: "1000000000000000000" }); // Send 1 ETH to Matching Engine

      //------------------------------ Deploy Contracts ------------------------------//

      // ErrorLibrary
      errorLibrary = await new Error__factory(admin).deploy();

      // MockToken
      mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed(), "Payment Token", "PT");
      mockVerifier = await new MockVerifier__factory(admin).deploy();

      // StakingManager
      const StakingManager = await ethers.getContractFactory("StakingManager");
      const _stakingManager = await upgrades.deployProxy(StakingManager, [], {
        kind: "uups",
        initializer: false,
      });
      stakingManager = StakingManager__factory.connect(await _stakingManager.getAddress(), admin);

      // NativeStaking
      const NativeStaking = await ethers.getContractFactory("NativeStaking");
      const _nativeStaking = await upgrades.deployProxy(NativeStaking, [], {
        kind: "uups",
        initializer: false,
      });
      nativeStaking = NativeStaking__factory.connect(await _nativeStaking.getAddress(), admin);

      // SymbioticStaking
      const SymbioticStaking = await ethers.getContractFactory("SymbioticStaking");
      const _symbioticStaking = await upgrades.deployProxy(SymbioticStaking, [], {
        kind: "uups",
        initializer: false,
      });
      symbioticStaking = SymbioticStaking__factory.connect(await _symbioticStaking.getAddress(), admin);

      // SymbioticStakingReward
      const SymbioticStakingReward = await ethers.getContractFactory("SymbioticStakingReward");
      const _symbioticStakingReward = await upgrades.deployProxy(SymbioticStakingReward, [], {
        kind: "uups",
        initializer: false,
      });
      symbioticStakingReward = SymbioticStakingReward__factory.connect(await _symbioticStakingReward.getAddress(), admin);


      // EntityKeyRegistry
      const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
      const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
      const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
        kind: "uups",
        constructorArgs: [await mockAttestationVerifier.getAddress()],
      });
      entityRegistry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

      // ProverRegistry
      const ProverRegistryContract = await ethers.getContractFactory("ProverRegistry");
      const proverProxy = await upgrades.deployProxy(ProverRegistryContract, [], {
        kind: "uups",
        constructorArgs: [await mockToken.getAddress(), await entityRegistry.getAddress()],
        initializer: false,
      });
      proverRegistry = ProverRegistry__factory.connect(await proverProxy.getAddress(), signers[0]);

      // ProofMarketplace
      const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
      const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
        kind: "uups",
        constructorArgs: [
          await mockToken.getAddress(),
          marketCreationCost.toString(),
          await treasury.getAddress(),
          await proverRegistry.getAddress(),
          await entityRegistry.getAddress(),
        ],
        initializer: false,
      });

      proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), signers[0]);

      const dispute = await new Dispute__factory(admin).deploy(await entityRegistry.getAddress());

      //------------------------------ Initialize Contracts ------------------------------//

      // StakingManager
      await stakingManager.initialize(
        await admin.getAddress(),
        await proofMarketplace.getAddress(),
        await symbioticStaking.getAddress(),
        await mockToken.getAddress(),
      );

      // PROVER_REGISTRY_ROLE to ProverRegistry
      await stakingManager.grantRole(await stakingManager.PROVER_REGISTRY_ROLE(), await proverRegistry.getAddress());

      // SymbioticStaking
      await symbioticStaking.initialize(
        await admin.getAddress(),
        await mockAttestationVerifier.getAddress(),
        await proofMarketplace.getAddress(),
        await stakingManager.getAddress(),
        await symbioticStakingReward.getAddress(),
        await mockToken.getAddress(),
      );

      // SymbioticStakingReward
      await symbioticStakingReward.initialize(
        await admin.getAddress(),
        await proofMarketplace.getAddress(),
        await symbioticStaking.getAddress(),
        await mockToken.getAddress(),
      );

      // ProverRegistry
      await proverRegistry.initialize(await admin.getAddress(), await proofMarketplace.getAddress(), await stakingManager.getAddress());

      // ProofMarketplace
      await proofMarketplace.initialize(await admin.getAddress());

      //-------------------------------------- Config --------------------------------------//
      /* StakingManager */
      await stakingManager.addStakingPool(await nativeStaking.getAddress());
      await stakingManager.addStakingPool(await symbioticStaking.getAddress());

      //-------------------------------------- Setup --------------------------------------//

      expect(ethers.isAddress(await proofMarketplace.getAddress())).is.true;

      // Transfer market creation cost to `marketCreator` ()
      await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed());

      // KEY_REGISTER_ROLE to ProofMarketplace and ProverRegistry
      await entityRegistry.connect(admin).grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proofMarketplace.getAddress());

      // KEY_REGISTER_ROLE to ProverRegistry
      await entityRegistry.connect(admin).grantRole(await entityRegistry.KEY_REGISTER_ROLE(), await proverRegistry.getAddress());

      // UPDATER_ROLE to admin
      await proofMarketplace.connect(admin).grantRole(await proofMarketplace.UPDATER_ROLE(), await admin.getAddress());

      // SYMBIOTIC_STAKING_ROLE to SymbioticStaking
      await proofMarketplace.connect(admin).grantRole(await proofMarketplace.SYMBIOTIC_STAKING_ROLE(), await symbioticStaking.getAddress());

      // SYMBIOTIC_STAKING_REWARD_ROLE to SymbioticStakingReward
      await proofMarketplace
        .connect(admin)
        .grantRole(await proofMarketplace.SYMBIOTIC_STAKING_REWARD_ROLE(), await symbioticStakingReward.getAddress());
    });
  });

  describe("Staking Manager: Public Market", () => {
    let prover: Signer;
    let reward = new BigNumber(10).pow(20).multipliedBy(3);
    let marketId: string;

    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 1000; // in blocks
    let maxTimeForProofGeneration = 10000; // in blocks

    beforeEach(async () => {
      // Send reward to prover
      prover = signers[5];
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), reward.toFixed());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB
      marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).toFixed();

      // Approve marketplace for market creation cost
      await mockToken.connect(marketCreator).approve(await proofMarketplace.getAddress(), marketCreationCost.toFixed());

      // Create Marketplace
      await proofMarketplace
        .connect(marketCreator)
        .createMarketplace(
          marketBytes,
          await mockVerifier.getAddress(),
          penaltyForNotComputingProof,
          new MockEnclave(MockProverPCRS).getPcrRlp(),
          ivsEnclave.getPcrRlp(),
        );

      // Skip market activation delay
      let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
      await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());

      // Create Ask Request
      const latestBlock = await ethers.provider.getBlockNumber();
      const askIdToBeGenerated = await proofMarketplace.bidCounter();

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

      await proofMarketplace.connect(admin).updateCostPerBytes(1, 1000);

      const platformFee = await proofMarketplace.getPlatformFee(1, askRequest, secretInfo, aclInfo);
      await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee);

      await mockToken
        .connect(prover)
        .approve(await proofMarketplace.getAddress(), new BigNumber(platformFee.toString()).plus(reward).toFixed());
      
        await expect(proofMarketplace.connect(prover).createBid(askRequest, 1, secretInfo, aclInfo))
        .to.emit(proofMarketplace, "BidCreated")
        .withArgs(askIdToBeGenerated, true, "0x2345", "0x21")
        .to.emit(mockToken, "Transfer")
        .withArgs(await prover.getAddress(), await proofMarketplace.getAddress(), new BigNumber(platformFee.toString()).plus(reward));

      expect((await proofMarketplace.listOfBid(askIdToBeGenerated)).state).to.equal(1); // 1 means create state
    });

    // it()
  });
});
