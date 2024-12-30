import { expect } from "chai";
import { ethers } from "hardhat";
import { Provider, Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  Error,
  ProverRegistry,
  MockToken,
  PriorityLog,
  ProofMarketplace,
  TransferVerifier__factory,
  EntityKeyRegistry,
  Transfer_verifier_wrapper__factory,
  IVerifier__factory,
  IVerifier,
  SymbioticStakingReward,
  SymbioticStaking,
  NativeStaking,
  StakingManager,
} from "../typechain-types";

import {
  ProverData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockProverPCRS,
  MockMEPCRS,
  proverDataToBytes,
  proverFamilyId,
  ivsFamilyId,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

describe("Checking Case where prover and ivs image is same", () => {
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

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let proverData: ProverData;

  const ivsAndProverEnclaveCombined = new MockEnclave(MockProverPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);

  const godEnclave = new MockEnclave(GodEnclavePCRS);

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const proverStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const proverSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const proverComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);

  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByProver = new BigNumber(10).pow(18).multipliedBy(199);

  beforeEach(async () => {
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

    await admin.sendTransaction({ to: ivsAndProverEnclaveCombined.getAddress(), value: "1000000000000000000" });
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
      proverStakingAmount,
      proverSlashingPenalty,
      treasuryAddress,
      marketCreationCost,
      marketCreator,
      marketDataToBytes(marketSetupData),
      marketSetupData.inputOuputVerifierUrl,
      iverifier,
      generator,
      proverDataToBytes(proverData),
      ivsAndProverEnclaveCombined, // USED AS IVS HERE
      matchingEngineEnclave,
      ivsAndProverEnclaveCombined, // USED AS GENERATOR HERE
      minRewardByProver,
      proverComputeAllocation,
      computeGivenToNewMarket,
      godEnclave,
    );

    proofMarketplace = data.proofMarketplace;
    proverRegistry = data.proverRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;
    stakingManager = data.stakingManager;
    nativeStaking = data.nativeStaking;
    symbioticStaking = data.symbioticStaking;
    symbioticStakingReward = data.symbioticStakingReward;

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });

  it("Add new images for provers and ivs", async () => {
    const newProverImages = [MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs()].map(
      (a) => new MockEnclave(a),
    );

    const newIvsImages = [MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs(), MockEnclave.someRandomPcrs()].map(
      (a) => new MockEnclave(a),
    );

    await expect(proofMarketplace.connect(admin).addExtraImages(marketId, [], [])).to.be.revertedWithCustomError(
      proofMarketplace,
      "OnlyMarketCreator",
    );

    await expect(
      proofMarketplace.connect(marketCreator).addExtraImages(
        marketId,
        newProverImages.map((a) => a.getPcrRlp()),
        newIvsImages.map((a) => a.getPcrRlp()),
      ),
    ).to.not.be.reverted;

    for (let index = 0; index < newProverImages.length; index++) {
      const prover = newProverImages[index];
      const isAllowed = await entityKeyRegistry.isImageInFamily(prover.getImageId(), proverFamilyId(marketId));
      expect(isAllowed).is.true;
    }

    for (let index = 0; index < newIvsImages.length; index++) {
      const ivs = newIvsImages[index];
      const isAllowed = await entityKeyRegistry.isImageInFamily(ivs.getImageId(), ivsFamilyId(marketId));
      expect(isAllowed).is.true;
    }
  });

  it("Check events during adding and removing extra images", async () => {
    const newProver = new MockEnclave(MockEnclave.someRandomPcrs());
    const newIvs = new MockEnclave(MockEnclave.someRandomPcrs());

    await expect(proofMarketplace.connect(marketCreator).addExtraImages(marketId, [newProver.getPcrRlp()], [newIvs.getPcrRlp()]))
      .to.emit(proofMarketplace, "AddExtraProverImage")
      .withArgs(marketId, newProver.getImageId())
      .to.emit(proofMarketplace, "AddExtraIVSImage")
      .withArgs(marketId, newIvs.getImageId());

    await expect(proofMarketplace.connect(marketCreator).removeExtraImages(marketId, [newProver.getPcrRlp()], [newIvs.getPcrRlp()]))
      .to.emit(proofMarketplace, "RemoveExtraProverImage")
      .withArgs(marketId, newProver.getImageId())
      .to.emit(proofMarketplace, "RemoveExtraIVSImage")
      .withArgs(marketId, newIvs.getImageId());
  });

  it("Cannot remove default market id", async () => {
    await expect(proofMarketplace.connect(admin).removeExtraImages(marketId, [], [])).to.revertedWithCustomError(
      proofMarketplace,
      "OnlyMarketCreator",
    );

    await expect(
      proofMarketplace.connect(marketCreator).removeExtraImages(marketId, [ivsAndProverEnclaveCombined.getPcrRlp()], []),
    ).to.revertedWithCustomError(proofMarketplace, "CannotRemoveDefaultImageFromMarket");
    await expect(
      proofMarketplace.connect(marketCreator).removeExtraImages(marketId, [], [ivsAndProverEnclaveCombined.getPcrRlp()]),
    ).to.revertedWithCustomError(proofMarketplace, "CannotRemoveDefaultImageFromMarket");
  });

  describe("Submit Proof For invalid request", () => {
    let bidId: string;
    const updateIvsKey = async (ivsEnclave: MockEnclave) => {
      // use any enclave here as AV is mocked
      let ivsAttestationBytes = await ivsEnclave.getVerifiedAttestation(godEnclave); // means ivs should get verified attestation from noUseEnclave

      let types = ["bytes", "address"];
      let values = [ivsAttestationBytes, await generator.getAddress()];

      let abicode = new ethers.AbiCoder();
      let encoded = abicode.encode(types, values);
      let digest = ethers.keccak256(encoded);
      let signature = await ivsEnclave.signMessage(ethers.getBytes(digest));

      // use any enclave to get verfied attestation as mockAttesationVerifier is used here
      await expect(proverRegistry.connect(generator).addIvsKey(marketId, ivsAttestationBytes, signature))
        .to.emit(proverRegistry, "IvKeyAdded")
        .withArgs(marketId, ivsEnclave.getAddress());
    };

    beforeEach(async () => {
      let abiCoder = new ethers.AbiCoder();
      let assignmentExpiry = 100; // in blocks
      let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
      let maxTimeForProofGeneration = 10000; // in blocks
      const latestBlock = await ethers.provider.getBlockNumber();

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

      bidId = await setup.createBid(
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
        generator,
      );
    });
    it("Submit proof for invalid requests directly from prover", async () => {
      const bidData = await proofMarketplace.listOfBid(bidId);
      const types = ["uint256", "bytes"];

      const values = [bidId, bidData.bid.proverData];

      const abicode = new ethers.AbiCoder();
      const encoded = abicode.encode(types, values);
      const digest = ethers.keccak256(encoded);
      const signature = await ivsAndProverEnclaveCombined.signMessage(ethers.getBytes(digest));

      // TODO
      // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

      await expect(proofMarketplace.submitProofForInvalidInputs(bidId, signature)).to.emit(proofMarketplace, "InvalidInputsDetected");
    });

    it("Submit proof for invalid requests directly from new generators added by market maker", async () => {
      const newProverImage = new MockEnclave(MockEnclave.someRandomPcrs());
      await proofMarketplace
        .connect(marketCreator)
        .addExtraImages(marketId, [newProverImage.getPcrRlp()], [newProverImage.getPcrRlp()]);

      await updateIvsKey(newProverImage);

      const bidData = await proofMarketplace.listOfBid(bidId);
      const types = ["uint256", "bytes"];

      const values = [bidId, bidData.bid.proverData];

      const abicode = new ethers.AbiCoder();
      const encoded = abicode.encode(types, values);
      const digest = ethers.keccak256(encoded);
      const signature = await newProverImage.signMessage(ethers.getBytes(digest));

      await expect(proofMarketplace.submitProofForInvalidInputs(bidId, signature)).to.emit(proofMarketplace, "InvalidInputsDetected");
    });

    it("Should fail to ecies key when the prover image is not added by market creator", async () => {
      const newProverImage = new MockEnclave(MockEnclave.someRandomPcrs());
      let proverAttestationBytes = await newProverImage.getVerifiedAttestation(godEnclave);

      let types = ["bytes", "address"];

      let values = [proverAttestationBytes, await prover.getAddress()];

      let abicode = new ethers.AbiCoder();
      let encoded = abicode.encode(types, values);
      let digest = ethers.keccak256(encoded);
      let signature = await newProverImage.signMessage(ethers.getBytes(digest));

      await expect(
        proverRegistry.connect(generator).updateEncryptionKey(marketId, proverAttestationBytes, signature),
      ).to.be.revertedWithCustomError(proverRegistry, "IncorrectImageId");
    });

    it("Can't add same extra image twice", async () => {
      const newProverImage = new MockEnclave(MockEnclave.someRandomPcrs());
      await proofMarketplace
        .connect(marketCreator)
        .addExtraImages(marketId, [newProverImage.getPcrRlp()], [newProverImage.getPcrRlp()]);

      await expect(
        proofMarketplace.connect(marketCreator).addExtraImages(marketId, [newProverImage.getPcrRlp()], [newProverImage.getPcrRlp()]),
      )
        .to.be.revertedWithCustomError(proofMarketplace, "ImageAlreadyInFamily")
        .withArgs(newProverImage.getImageId(), proverFamilyId(marketId));
    });

    it("Can't add same extra ivs image twice", async () => {
      const newIvsImage = new MockEnclave(MockEnclave.someRandomPcrs());
      await proofMarketplace.connect(marketCreator).addExtraImages(marketId, [], [newIvsImage.getPcrRlp()]);

      await expect(proofMarketplace.connect(marketCreator).addExtraImages(marketId, [], [newIvsImage.getPcrRlp()]))
        .to.be.revertedWithCustomError(proofMarketplace, "ImageAlreadyInFamily")
        .withArgs(newIvsImage.getImageId(), ivsFamilyId(marketId));
    });

    it("Update Ecies key when the prover image is updated", async () => {
      const newProverImage = new MockEnclave(MockEnclave.someRandomPcrs());
      await proofMarketplace
        .connect(marketCreator)
        .addExtraImages(marketId, [newProverImage.getPcrRlp()], [newProverImage.getPcrRlp()]);

      let proverAttestationBytes = await newProverImage.getVerifiedAttestation(godEnclave);

      let types = ["bytes", "address"];

      let values = [proverAttestationBytes, await generator.getAddress()];

      let abicode = new ethers.AbiCoder();
      let encoded = abicode.encode(types, values);
      let digest = ethers.keccak256(encoded);
      let signature = await newProverImage.signMessage(ethers.getBytes(digest));

      await expect(proverRegistry.connect(generator).updateEncryptionKey(marketId, proverAttestationBytes, signature))
        .to.emit(entityKeyRegistry, "UpdateKey")
        .withArgs(await generator.getAddress(), marketId);
    });

    describe("Only New IVS added by market maker", () => {
      const newIvsImage = new MockEnclave(MockEnclave.someRandomPcrs());
      beforeEach(async () => {
        await proofMarketplace.connect(marketCreator).addExtraImages(marketId, [], [newIvsImage.getPcrRlp()]);

        await updateIvsKey(newIvsImage);
      });

      it("Submit proof for invalid requests directly from if only new ivs added by market maker", async () => {
        const bidData = await proofMarketplace.listOfBid(bidId);
        const types = ["uint256", "bytes"];

        const values = [bidId, bidData.bid.proverData];

        const abicode = new ethers.AbiCoder();
        const encoded = abicode.encode(types, values);
        const digest = ethers.keccak256(encoded);
        const signature = await newIvsImage.signMessage(ethers.getBytes(digest));

        // TODO
        // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

        await expect(proofMarketplace.submitProofForInvalidInputs(bidId, signature)).to.emit(proofMarketplace, "InvalidInputsDetected");
      });

      it("Should Fail: can't submit proofs if signature os invalid", async () => {
        const signature =
          "0x0000111100001111000011110000111100001111000011110000111100001111000011110000111100001111000011110000111100001111000011110000ddddff";

        // TODO
        // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

        await expect(proofMarketplace.submitProofForInvalidInputs(bidId, signature)).to.revertedWithCustomError(
          proofMarketplace,
          "ECDSAInvalidSignature",
        );
      });

      it("Submit proof for invalid requests, should fail if the image is revoked by market maker", async () => {
        await expect(proofMarketplace.connect(marketCreator).removeExtraImages(marketId, [], [newIvsImage.getPcrRlp()]))
          .to.emit(entityKeyRegistry, "EnclaveImageRemovedFromFamily")
          .withArgs(newIvsImage.getImageId(), ivsFamilyId(marketId));

        const bidData = await proofMarketplace.listOfBid(bidId);
        const types = ["uint256", "bytes"];

        const values = [bidId, bidData.bid.proverData];

        const abicode = new ethers.AbiCoder();
        const encoded = abicode.encode(types, values);
        const digest = ethers.keccak256(encoded);
        const signature = await newIvsImage.signMessage(ethers.getBytes(digest));

        // TODO
        // await proofMarketplace.flush(await treasury.getAddress()); // remove anything if is already there

        await expect(proofMarketplace.submitProofForInvalidInputs(bidId, signature)).to.revertedWithCustomError(
          entityKeyRegistry,
          "AttestationAutherImageNotInFamily",
        );
      });
    });
  });
});
