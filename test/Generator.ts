import { ethers, platform, upgrades } from "hardhat";
import { Signer, keccak256 } from "ethers";
import {
  Error,
  Error__factory,
  GeneratorRegistry,
  GeneratorRegistry__factory,
  MockToken,
  MockToken__factory,
  ProofMarketPlace,
  ProofMarketPlace__factory,
  MockAttestationVerifier__factory,
  RsaRegistry__factory,
  MockVerifier__factory,
} from "../typechain-types";
import BigNumber from "bignumber.js";
import { bytesToHexString, generateRandomBytes, jsonToBytes, splitHexString } from "../helpers";
import { expect } from "chai";

const zeroAddress = "0x0000000000000000000000000000000000000000";
describe("Generator", () => {
  let signers: Signer[];
  let admin: Signer;
  let generator: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;

  let errorLibrary: Error;

  let generatorRegistry: GeneratorRegistry;
  let stakingToken: MockToken;
  let paymentToken: MockToken;

  let tokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(4);
  let marketCreationCost: BigNumber = new BigNumber(10).pow(20).multipliedBy(5);

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    generator = signers[2];
    treasury = signers[3];

    errorLibrary = await new Error__factory(admin).deploy();
    stakingToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());
    paymentToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), tokenSupply.toFixed());

    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [await stakingToken.getAddress()],
      initializer: false,
    });
    generatorRegistry = GeneratorRegistry__factory.connect(await generatorProxy.getAddress(), signers[0]);
  });

  describe("++ Proof Market Place", () => {
    let proofMarketPlace: ProofMarketPlace;
    const compute = 1234;
    const proofCost = 100;
    const proofTimeInBlocks = 123;

    const generatorData = "0x0011";
    const stakingAmount = "100000";
    const slashingPenalty = "2999999";

    let marketId: string;

    let marketCreator: Signer;

    beforeEach(async () => {
      marketCreator = signers[8];
      const mockAttestationVerifier = await new MockAttestationVerifier__factory(admin).deploy();
      const rsaRegistry = await new RsaRegistry__factory(admin).deploy(await mockAttestationVerifier.getAddress());

      const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
      const proxy = await upgrades.deployProxy(ProofMarketPlace, [await admin.getAddress()], {
        kind: "uups",
        constructorArgs: [
          await paymentToken.getAddress(),
          await stakingToken.getAddress(),
          marketCreationCost.toString(),
          await treasury.getAddress(),
          await generatorRegistry.getAddress(),
          await rsaRegistry.getAddress(),
        ],
      });
      proofMarketPlace = ProofMarketPlace__factory.connect(await proxy.getAddress(), signers[0]);
      await generatorRegistry.connect(admin).initialize(await admin.getAddress(), await proofMarketPlace.getAddress());

      const marketBytes = "0x" + bytesToHexString(await generateRandomBytes(1024 * 10)); // 10 MB
      marketId = ethers.keccak256(marketBytes);
      const mockVerifier = await new MockVerifier__factory(admin).deploy();

      await paymentToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), marketCreationCost.toFixed(0));
      await paymentToken
        .connect(marketCreator)
        .approve(await proofMarketPlace.getAddress(), marketCreationCost.toFixed(0));
      await proofMarketPlace
        .connect(marketCreator)
        .createMarketPlace(marketBytes, await mockVerifier.getAddress(), slashingPenalty),
        await generatorRegistry.connect(generator).register(await generator.getAddress(), compute, generatorData);

      await stakingToken.connect(tokenHolder).transfer(await generator.getAddress(), stakingAmount);
      await stakingToken.connect(generator).approve(await generatorRegistry.getAddress(), stakingAmount);
      await generatorRegistry.connect(generator).stake(await generator.getAddress(), stakingAmount);
    });

    it("Join Market Place", async () => {
      await expect(
        generatorRegistry.connect(generator).joinMarketPlace(marketId, compute, proofCost, proofTimeInBlocks),
      )
        .to.emit(generatorRegistry, "JoinedMarketPlace")
        .withArgs(await generator.getAddress(), marketId, compute);
    });

    it("Should Fail Joining: If address is not a generator", async () => {
      await expect(
        generatorRegistry.connect(treasury).joinMarketPlace(marketId, compute, proofCost, proofTimeInBlocks),
      ).to.be.revertedWith(await errorLibrary.INVALID_GENERATOR());
    });

    it("Should Fail: Join Invalid Market ID", async () => {
      await expect(
        generatorRegistry
          .connect(generator)
          .joinMarketPlace(keccak256("0x123123123123"), compute, proofCost, proofTimeInBlocks),
      ).to.be.revertedWith(await errorLibrary.INVALID_MARKET());
    });

    it("Should Fail: Proposed Time and Resource Allocation can not be zero, proof cost can be", async () => {
      await expect(
        generatorRegistry.connect(generator).joinMarketPlace(marketId, compute, proofCost, 0),
      ).to.be.revertedWith(await errorLibrary.CANNOT_BE_ZERO());

      await expect(
        generatorRegistry.connect(generator).joinMarketPlace(marketId, 0, proofCost, proofTimeInBlocks),
      ).to.be.revertedWith(await errorLibrary.CANNOT_BE_ZERO());

      await expect(
        generatorRegistry.connect(generator).joinMarketPlace(marketId, compute, proofCost, proofTimeInBlocks),
      ).to.emit(generatorRegistry, "JoinedMarketPlace");
    });

    it("Should Fail: Can't declare more than compute", async () => {
      await expect(
        generatorRegistry
          .connect(generator)
          .joinMarketPlace(marketId, new BigNumber(compute).plus(11).toFixed(0), proofCost, proofTimeInBlocks),
      ).to.be.revertedWith(await errorLibrary.CAN_NOT_BE_MORE_THAN_DECLARED_COMPUTE());
    });
  });

  describe("Mock Proof Market Place Address", () => {
    let randomAddress: string;

    const generatorData = "0x123456";
    const declaredCompute = 10000;

    beforeEach(async () => {
      randomAddress = await signers[11].getAddress();
      await generatorRegistry.connect(admin).initialize(await admin.getAddress(), randomAddress);
    });

    it("Any one Register", async () => {
      await expect(
        generatorRegistry.connect(generator).register(await generator.getAddress(), declaredCompute, generatorData),
      )
        .to.emit(generatorRegistry, "RegisteredGenerator")
        .withArgs(await generator.getAddress());
    });

    it("Should Fail Registration: When reward address is 0", async () => {
      await expect(
        generatorRegistry.connect(generator).register(zeroAddress, declaredCompute, generatorData),
      ).to.be.revertedWith(await errorLibrary.CANNOT_BE_ZERO());
    });

    it("Should Fail Registration: When declared compute is 0", async () => {
      await expect(
        generatorRegistry.connect(generator).register(await generator.getAddress(), 0, generatorData),
      ).to.be.revertedWith(await errorLibrary.CANNOT_BE_ZERO());
    });

    it("Should Fail Registration: when generator data is 0", async () => {
      await expect(
        generatorRegistry.connect(generator).register(await generator.getAddress(), declaredCompute, "0x"),
      ).to.be.revertedWith(await errorLibrary.CANNOT_BE_ZERO());
    });

    it("Should Fail: Re-registration", async () => {
      await generatorRegistry.connect(generator).register(await generator.getAddress(), declaredCompute, generatorData);
      await expect(
        generatorRegistry.connect(generator).register(await generator.getAddress(), declaredCompute, generatorData),
      ).to.be.revertedWith(await errorLibrary.GENERATOR_ALREADY_EXISTS());
    });

    describe("Post Registration", () => {
      const stakingAmount = "1000";
      beforeEach(async () => {
        await generatorRegistry
          .connect(generator)
          .register(await generator.getAddress(), declaredCompute, generatorData);
      });

      it("Stake", async () => {
        await stakingToken.connect(tokenHolder).transfer(await generator.getAddress(), stakingAmount);
        await stakingToken.connect(generator).approve(await generatorRegistry.getAddress(), stakingAmount);

        await expect(generatorRegistry.connect(generator).stake(await generator.getAddress(), stakingAmount))
          .to.emit(generatorRegistry, "AddedStash")
          .withArgs(await generator.getAddress(), stakingAmount);
      });

      describe("Post Staking", () => {
        beforeEach(async () => {
          await stakingToken.connect(tokenHolder).transfer(await generator.getAddress(), stakingAmount);
          await stakingToken.connect(generator).approve(await generatorRegistry.getAddress(), stakingAmount);

          await generatorRegistry.connect(generator).stake(await generator.getAddress(), stakingAmount);
        });

        it("Unstake", async () => {
          await expect(generatorRegistry.connect(generator).unstake(await generator.getAddress(), stakingAmount))
            .to.emit(generatorRegistry, "RemovedStash")
            .withArgs(await generator.getAddress(), stakingAmount);
        });
      });
    });
  });
});
