import BigNumber from 'bignumber.js';
import {
  BytesLike,
  Signer,
  Wallet,
} from 'ethers';
import { ethers } from 'hardhat';

import {
  BridgeEnclavePCRS,
  GodEnclavePCRS,
  MarketData,
  marketDataToBytes,
  MockEnclave,
  MockIVSPCRS,
  MockMEPCRS,
  MockProverPCRS,
  ProverData,
  proverDataToBytes,
  setup,
} from '../helpers';
import * as transfer_verifier_inputs
  from '../helpers/sample/transferVerifier/transfer_inputs.json';
import * as transfer_verifier_proof
  from '../helpers/sample/transferVerifier/transfer_proof.json';
import { stakingSetup, submitSlashResult, submitVaultSnapshot, TaskSlashed, VaultSnapshot, toEthSignedMessageHash } from '../helpers/setup';
import {
  AttestationVerifier,
  EntityKeyRegistry,
  Error,
  IVerifier,
  IVerifier__factory,
  MockToken,
  NativeStaking,
  POND,
  PriorityLog,
  ProofMarketplace,
  ProverManager,
  StakingManager,
  SymbioticStaking,
  SymbioticStakingReward,
  Transfer_verifier_wrapper__factory,
  TransferVerifier__factory,
  WETH,
} from '../typechain-types';
import { expect } from 'chai';

describe("Staking", () => {
  let proofMarketplace: ProofMarketplace;
  let proverManager: ProverManager;
  let usdc: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;
  let iverifier: IVerifier;
  let attestationVerifier: AttestationVerifier;
  let stakingManager: StakingManager;
  let nativeStaking: NativeStaking;
  let symbioticStaking: SymbioticStaking;
  let symbioticStakingReward: SymbioticStakingReward;

  let pool1: string;
  let pool2: string;

  let pond: POND;
  let weth: WETH;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let refundReceiver: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let proverData: ProverData;
  let imageId: BytesLike;

  /* Enclaves */
  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const proverEnclave = new MockEnclave(MockProverPCRS);
  const godEnclave = new MockEnclave(GodEnclavePCRS);
  const bridgeEnclave = new MockEnclave(BridgeEnclavePCRS);

  /* Config */
  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const proverStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const proverSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const proverComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);
  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);
  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByProver = new BigNumber(10).pow(18).multipliedBy(199);

  const refreshSetup = async (
    modifiedComputeGivenToNewMarket = computeGivenToNewMarket,
    modifiedProverStakingAmount = proverStakingAmount,
  ): Promise<void> => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    treasury = signers[2];
    marketCreator = signers[3];
    prover = signers[4];
    refundReceiver = signers[5];

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
      modifiedProverStakingAmount,
      proverSlashingPenalty,
      treasuryAddress,
      marketCreationCost,
      marketCreator,
      marketDataToBytes(marketSetupData),
      marketSetupData.inputOuputVerifierUrl,
      iverifier,
      prover,
      proverDataToBytes(proverData),
      ivsEnclave,
      matchingEngineEnclave,
      proverEnclave,
      minRewardByProver,
      proverComputeAllocation,
      modifiedComputeGivenToNewMarket,
      godEnclave,
    );

    attestationVerifier = data.attestationVerifier;
    entityKeyRegistry = data.entityKeyRegistry;
    proofMarketplace = data.proofMarketplace;
    proverManager = data.proverManager;
    usdc = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;

    /* Staking Contracts */
    stakingManager = data.stakingManager;
    nativeStaking = data.nativeStaking;
    symbioticStaking = data.symbioticStaking;
    symbioticStakingReward = data.symbioticStakingReward;

    imageId = await symbioticStaking.getImageId(bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);
    pool1 = ethers.Wallet.createRandom().address;
    pool2 = ethers.Wallet.createRandom().address;

    await attestationVerifier.whitelistEnclaveImage(bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);
    await attestationVerifier.whitelistEnclaveKey(bridgeEnclave.getUncompressedPubkey(), imageId);
    await symbioticStaking['addEnclaveImage(bytes,bytes,bytes)'](bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();
    ({ pond, weth } = await stakingSetup(admin, stakingManager, nativeStaking, symbioticStaking, symbioticStakingReward));
  };

  describe("Staking Manager", () => {
    beforeEach(async () => {
      await refreshSetup();
    });

    describe("Default Admin Role", () => {

      describe("Adding new Staking Pool", async () => {
        const pool1_weight = 100;
        const pool2_weight = 200;
        let initialPoolRewardShareSum: BigNumber;

        beforeEach(async () => {
          initialPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
        });

        it("should store new pool data", async () => {
          const tx = await stakingManager.addStakingPool(pool1, pool1_weight);

          const poolConfig = await stakingManager.getPoolConfig(pool1);
          expect(poolConfig.rewardShare).to.equal(pool1_weight);
          expect(poolConfig.enabled).to.equal(false);
          expect(tx).to.emit(stakingManager, "StakingPoolAdded").withArgs(pool1);
        });

        it("initialPoolRewardShareSum should not be changed", async () => {
          await stakingManager.addStakingPool(pool1, pool1_weight);

          let currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
          expect(currentPoolRewardShareSum).to.be.equal(initialPoolRewardShareSum);

          await stakingManager.addStakingPool(pool2, pool2_weight);
          currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
          expect(currentPoolRewardShareSum).to.be.equal(initialPoolRewardShareSum);
        });

        it("should revert if pool already exists", async () => {
          await stakingManager.addStakingPool(pool1, pool1_weight);
          await expect(stakingManager.addStakingPool(pool1, pool2_weight)).to.be.revertedWithCustomError(errorLibrary, "PoolAlreadyExists");
        });
      });

      describe("Removing Staking Pool", async () => {
        const pool1_weight = 100;
        const pool2_weight = 200;
        let initialPoolRewardShareSum: BigNumber;

        beforeEach(async () => {
          await stakingManager.addStakingPool(pool1, pool1_weight);
          initialPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
        });
        
        it("should decrease poolRewardShareSum", async () => {
          let currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
          expect(currentPoolRewardShareSum).to.be.equal(initialPoolRewardShareSum);

          await stakingManager.removeStakingPool(pool1);
          currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
          expect(currentPoolRewardShareSum).to.be.equal(initialPoolRewardShareSum.minus(pool1_weight));
        });

        it("should revert if pool does not exist", async () => {
          await expect(stakingManager.removeStakingPool(pool2)).to.be.revertedWithCustomError(errorLibrary, "PoolDoesNotExist");
        });

        it("should delete pool data", async () => {
          await stakingManager.removeStakingPool(pool1);

          const poolConfig = await stakingManager.getPoolConfig(pool1);
          expect(poolConfig.rewardShare).to.be.equal(0);
          expect(poolConfig.enabled).to.be.equal(false);
        });

        it("should emit event", async () => {
          await expect(stakingManager.removeStakingPool(pool1)).to.emit(stakingManager, "StakingPoolRemoved").withArgs(pool1);
        });
      });

      describe("Setting Pool Enabled", async () => {
        const pool1_weight = 100;
        const pool2_weight = 200;
        let initialPoolRewardShareSum: BigNumber;

        beforeEach(async () => {
          await stakingManager.addStakingPool(pool1, pool1_weight);
          initialPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
        });

        describe("Enabling Staking Pool", async () => {

          it("should enable pool", async () => {
            await stakingManager.setPoolEnabled(pool1, true);
            const poolConfig = await stakingManager.getPoolConfig(pool1);
            expect(poolConfig.enabled).to.be.equal(true);
          });

          // TODO: fix to PoolDoesNotExist
          it("should revert if pool does not exist", async () => {
            await expect(stakingManager.setPoolEnabled(pool2, true)).to.be.revertedWithCustomError(errorLibrary, "PoolDoesNotExist");
          });
          
          it("should revert if pool is already enabled", async () => {
            await stakingManager.setPoolEnabled(pool1, true);
            await expect(stakingManager.setPoolEnabled(pool1, true)).to.be.revertedWithCustomError(errorLibrary, "PoolAlreadyEnabled");
          });

          it("should emit event", async () => {
            await expect(stakingManager.setPoolEnabled(pool1, true)).to.emit(stakingManager, "PoolEnabledSet").withArgs(pool1, true);
          });

          it("should increase poolRewardShareSum", async () => {
            await stakingManager.setPoolEnabled(pool1, true);
            let currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
            expect(currentPoolRewardShareSum).to.be.equal(initialPoolRewardShareSum.plus(pool1_weight));
          });
        });

        describe("Disabling Staking Pool", async () => {

          beforeEach(async () => {
            await stakingManager.setPoolEnabled(pool1, true);
          });

          it("should disable pool", async () => {
            await stakingManager.setPoolEnabled(pool1, false);
            const poolConfig = await stakingManager.getPoolConfig(pool1);
            expect(poolConfig.enabled).to.be.equal(false);
          });

          it("should revert if pool is already disabled", async () => {
            await stakingManager.setPoolEnabled(pool1, false);
            await expect(stakingManager.setPoolEnabled(pool1, false)).to.be.revertedWithCustomError(errorLibrary, "PoolAlreadyDisabled");
          });

          it("should emit event", async () => {
            await expect(stakingManager.setPoolEnabled(pool1, false)).to.emit(stakingManager, "PoolEnabledSet").withArgs(pool1, false);
          });

          it("should decrease poolRewardShareSum", async () => {
            let currentPoolRewardShareSum = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
            await stakingManager.setPoolEnabled(pool1, false);
            expect(await stakingManager.poolRewardShareSum()).to.be.equal(currentPoolRewardShareSum.minus(pool1_weight));
          });

          it("should still store pool config", async () => {
            await stakingManager.setPoolEnabled(pool1, false);

            const poolConfig = await stakingManager.getPoolConfig(pool1);
            expect(poolConfig.enabled).to.be.equal(false);
            expect(poolConfig.rewardShare).to.be.equal(pool1_weight);
          });
        });
      });

      describe("Setting Pool Reward Share", async () => {
        const pool1_weight = 100;
        const pool2_weight = 200;
        const pool1_weight_after = 150;

        beforeEach(async () => {
          // Add pool1
          await stakingManager.addStakingPool(pool1, pool1_weight);
        });

        describe("When Pool is already enabled", async () => {  
          beforeEach(async () => {
            // Enable pool1
            await stakingManager.setPoolEnabled(pool1, true);
          });

          it("should set pool reward share", async () => {
            await stakingManager.setPoolRewardShare(pool1, pool1_weight_after);
            const poolConfig = await stakingManager.getPoolConfig(pool1);
            expect(poolConfig.rewardShare).to.be.equal(pool1_weight_after);
          });

          it("should emit event", async () => {
            await expect(stakingManager.setPoolRewardShare(pool1, pool1_weight_after)).to.emit(stakingManager, "PoolRewardShareSet").withArgs(pool1, pool1_weight_after);
          });

          it("should modify poolRewardShareSum", async () => {
            const poolRewardShareSumBefore = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
            await stakingManager.setPoolRewardShare(pool1, pool1_weight_after);
            expect(await stakingManager.poolRewardShareSum()).to.be.equal(poolRewardShareSumBefore.minus(pool1_weight).plus(pool1_weight_after));
          });
        });

        describe("When Pool is Disabled", async () => {
          // Pool is disabled as it's not enabled
          
          it("should set pool reward share", async () => {
            await stakingManager.setPoolRewardShare(pool1, pool1_weight_after);
            const poolConfig = await stakingManager.getPoolConfig(pool1);
            expect(poolConfig.rewardShare).to.be.equal(pool1_weight_after);
          });

          it("should emit event", async () => {
            await expect(stakingManager.setPoolRewardShare(pool1, pool1_weight_after)).to.emit(stakingManager, "PoolRewardShareSet").withArgs(pool1, pool1_weight_after);
          });

          it("should not affect poolRewardShareSum", async () => {
            const poolRewardShareSumBefore = new BigNumber((await stakingManager.poolRewardShareSum()).toString());
            await stakingManager.setPoolRewardShare(pool1, pool1_weight_after);
            expect(await stakingManager.poolRewardShareSum()).to.be.equal(poolRewardShareSumBefore);
          });

          it("should revert if pool does not exist", async () => {
            await expect(stakingManager.setPoolRewardShare(pool2, pool1_weight_after)).to.be.revertedWithCustomError(errorLibrary, "PoolDoesNotExist");
          });
        });
      });

      describe("Setting Contract Addresses", async () => {

        describe("Setting Proof Marketplace", async () => {
          it("should set proofMarketplace", async () => {
            const tx = await stakingManager.setProofMarketplace(proofMarketplace.getAddress());
            expect(tx).to.emit(stakingManager, "ProofMarketplaceSet").withArgs(proofMarketplace.getAddress());
          });

          it("should emit event", async () => {
            await expect(stakingManager.setProofMarketplace(proofMarketplace.getAddress())).to.emit(stakingManager, "ProofMarketplaceSet").withArgs(proofMarketplace.getAddress());
          });
        });

        describe("Setting Fee Token", async () => {
          let feeToken: string;

          beforeEach(async () => {
            feeToken = await ethers.Wallet.createRandom().getAddress();
          });

          it("should set feeToken", async () => {
            const tx = await stakingManager.setFeeToken(feeToken);
            expect(tx).to.emit(stakingManager, "FeeTokenSet").withArgs(feeToken);
          });

          it("should emit event", async () => {
            await expect(stakingManager.setFeeToken(feeToken)).to.emit(stakingManager, "FeeTokenSet").withArgs(feeToken);
          });
        });
      });

      describe("Emergency Withdraw", async () => {
        it("should revert if token address is zero", async () => {
          await expect(stakingManager.emergencyWithdraw(ethers.ZeroAddress, ethers.ZeroAddress)).to.be.revertedWithCustomError(errorLibrary, "ZeroTokenAddress");
        });

        it("should revert if to address is zero", async () => {
          await expect(stakingManager.emergencyWithdraw(ethers.ZeroAddress, ethers.ZeroAddress)).to.be.revertedWithCustomError(errorLibrary, "ZeroToAddress");
        });

        it.only("should transfer all tokens to the to address", async () => {
          // transfer some tokens to the staking manager
          await usdc.connect(tokenHolder).transfer(stakingManager.getAddress(), new BigNumber(10).pow(18).multipliedBy(100).toString());

          const tokenBalanceBefore = await usdc.balanceOf(await stakingManager.getAddress());
          const refundReceiverBalanceBefore = await usdc.balanceOf(refundReceiver.getAddress());
          expect(tokenBalanceBefore).to.be.equal(new BigNumber(10).pow(18).multipliedBy(100).toString());

          await stakingManager.emergencyWithdraw(usdc.getAddress(), refundReceiver.getAddress());

          const tokenBalanceAfter = await usdc.balanceOf(await stakingManager.getAddress());
          const refundReceiverBalanceAfter = await usdc.balanceOf(refundReceiver.getAddress());
          expect(tokenBalanceAfter).to.be.equal(0);
          expect(refundReceiverBalanceAfter).to.be.equal(new BigNumber(10).pow(18).multipliedBy(100).toString());
        });
      });
    });

  });
});

