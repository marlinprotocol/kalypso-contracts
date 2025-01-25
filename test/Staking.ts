import BigNumber from 'bignumber.js';
import {
  BytesLike,
  Signer,
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

  let vault1Address: string;
  let vault2Address: string;

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
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const generatorComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);
  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);
  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByGenerator = new BigNumber(10).pow(18).multipliedBy(199);

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
      modifiedGeneratorStakingAmount,
      generatorSlashingPenalty,
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
      minRewardByGenerator,
      generatorComputeAllocation,
      modifiedComputeGivenToNewMarket,
      godEnclave,
    );

    attestationVerifier = data.attestationVerifier;
    entityKeyRegistry = data.entityKeyRegistry;
    proofMarketplace = data.proofMarketplace;
    proverManager = data.proverManager;
    usdc = data.mockToken;
    priorityLog = data.priorityLog; // TODO
    errorLibrary = data.errorLibrary; // TODO

    /* Staking Contracts */
    stakingManager = data.stakingManager;
    nativeStaking = data.nativeStaking;
    symbioticStaking = data.symbioticStaking;
    symbioticStakingReward = data.symbioticStakingReward;

    imageId = await symbioticStaking.getImageId(bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);
    vault1Address = ethers.Wallet.createRandom().address;
    vault2Address = ethers.Wallet.createRandom().address;

    await attestationVerifier.whitelistEnclaveImage(bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);
    await attestationVerifier.whitelistEnclaveKey(bridgeEnclave.getUncompressedPubkey(), imageId);
    await symbioticStaking['addEnclaveImage(bytes,bytes,bytes)'](bridgeEnclave.pcrs[0], bridgeEnclave.pcrs[1], bridgeEnclave.pcrs[2]);

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();
    ({ pond, weth } = await stakingSetup(admin, stakingManager, nativeStaking, symbioticStaking, symbioticStakingReward));
  };

  describe("Vault Snapshot Submission", () => {
    let captureTimestamp: BigNumber;
    let lastBlockNumber: BigNumber;

    beforeEach(async () => {
      await refreshSetup();
    });

    describe("Enclave Key Verification", () => {
      it("should verify Enclave Key", async () => {
        const encoded = await bridgeEnclave.getMockAttestation();
        await attestationVerifier["verify(bytes)"](encoded);
      });

      it("should submit snapshot", async () => {
        captureTimestamp = new BigNumber((await ethers.provider.getBlock("latest"))?.timestamp ?? 0).minus(10);

        // 3 partial txs
        const numOfTxs = 3;

        const vaultSnapshots: VaultSnapshot[] = [
          {
            prover: await prover.getAddress(),
            vault: vault1Address,
            stakeToken: await pond.getAddress(),
            stakeAmount: new BigNumber(10).pow(18).multipliedBy(1000).toFixed(), // 1000 POND
          },
        ];

        await submitVaultSnapshot(symbioticStaking, bridgeEnclave, prover, {
          index: 0,
          numOfTxs,
          captureTimestamp: captureTimestamp.toString(),
          imageId: imageId.toString(),
          snapshotData: vaultSnapshots,
        });
      });

      it("should submit slash result", async () => {
        lastBlockNumber = new BigNumber((await ethers.provider.getBlock("latest"))?.number ?? 0).minus(10);
        captureTimestamp = new BigNumber((await ethers.provider.getBlock("latest"))?.timestamp ?? 0).minus(10);

        const taskSlashed: TaskSlashed[] = [];

        await submitSlashResult(symbioticStaking, bridgeEnclave, prover, {
          index: 0,
          numOfTxs: 1,
          captureTimestamp: captureTimestamp.toString(),
          lastBlockNumber: lastBlockNumber.toString(),
          imageId: imageId.toString(),
          slashResultData: taskSlashed,
        });
      });
    });
  });
});
