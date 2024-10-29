import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { AbiCoder, Signer } from "ethers";
import { BigNumber } from "bignumber.js";
import {
  AttestationVerifierZK__factory,
  EntityKeyRegistry,
  Error,
  GeneratorRegistry,
  IVerifier,
  IVerifier__factory,
  MockToken,
  PriorityLog,
  ProofMarketplace,
  Risc0_attestation_verifier_wrapper__factory,
  RiscZeroGroth16Verifier__factory,
  RiscZeroVerifierEmergencyStop__factory,
} from "../typechain-types";

import {
  GeneratorData,
  GodEnclavePCRS,
  MarketData,
  MockEnclave,
  MockGeneratorPCRS,
  MockIVSPCRS,
  MockMEPCRS,
  generatorDataToBytes,
  marketDataToBytes,
  setup,
  skipBlocks,
} from "../helpers";
// import * as attestation from "../helpers/sample/risc0/attestation_struct.json";
import * as attestation from "../helpers/sample/risc0/attestation.json";

describe("Proof Market Place for Attestation Verifier", () => {
  let proofMarketplace: ProofMarketplace;
  let generatorRegistry: GeneratorRegistry;
  let tokenToUse: MockToken;
  let priorityLog: PriorityLog;
  let errorLibrary: Error;
  let entityKeyRegistry: EntityKeyRegistry;

  let signers: Signer[];
  let admin: Signer;
  let tokenHolder: Signer;
  let treasury: Signer;
  let prover: Signer;
  let generator: Signer;

  let marketCreator: Signer;
  let marketSetupData: MarketData;
  let marketId: string;

  let generatorData: GeneratorData;

  let iverifier: IVerifier;

  const ivsEnclave = new MockEnclave(MockIVSPCRS);
  const matchingEngineEnclave = new MockEnclave(MockMEPCRS);
  const generatorEnclave = new MockEnclave(MockGeneratorPCRS);
  const godEnclave = new MockEnclave(GodEnclavePCRS);

  const totalTokenSupply: BigNumber = new BigNumber(10).pow(24).multipliedBy(9);
  const generatorStakingAmount: BigNumber = new BigNumber(10).pow(18).multipliedBy(1000).multipliedBy(2).minus(1231); // use any random number
  const generatorSlashingPenalty: BigNumber = new BigNumber(10).pow(16).multipliedBy(93).minus(182723423); // use any random number
  const marketCreationCost: BigNumber = new BigNumber(10).pow(18).multipliedBy(1213).minus(23746287365); // use any random number
  const generatorComputeAllocation = new BigNumber(10).pow(19).minus("12782387").div(123).multipliedBy(98);

  const computeGivenToNewMarket = new BigNumber(10).pow(19).minus("98897").div(9233).multipliedBy(98);

  const rewardForProofGeneration = new BigNumber(10).pow(18).multipliedBy(200);
  const minRewardByGenerator = new BigNumber(10).pow(18).multipliedBy(199);

  // TODO: save it somewhere latter
  let seal =
    "0x50bd17690fc93a31b96581f52f239398df9371f74911ab5e3d091635c64ec45984581cc61ac09b9dcc49da498801f6632b2bfd649d5233bb1cf11d9929c56aeca407449824612d2f596e36fa8f11a5f0403879582405cd079ab951c21820e75e6f16101b2b5cea06f6a903713ec4eb861aae32067b055de7ec1a498e9b44a472034ba3290e1ba95be9da41a533b7c8ebabdc87bc3a72d535d0963bc3576513337f26afca0358f2d9bb51e871bb479a0f358c4d13de21c8072b6ef2cc5adfa5adb87b4b0a2f94687025f3bd85b8d8d1e46919460f809348f0b11158990f2eda157b75ed1f26b3d1101276adec9085a4095110de700739128c4ae320a72e5d38d5d6eee755";
  let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
  // let journal_digest = "0xcd1b9da17add2f43e4feffed585dc72e07ebba44f7e10662630d986e1317e9dc";
  let journal_bytes =
    "0x00000192bd6ad011189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a65d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd166c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb0000";

  const type_input = ["bytes", "bytes32", "bytes"];
  let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal_bytes]);

  let inputBytes = attestation.attestation;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];
    tokenHolder = signers[1];
    treasury = signers[2];
    marketCreator = signers[3];
    prover = signers[4];
    generator = signers[5];

    marketSetupData = {
      zkAppName: "risc0 attestation zk verifier",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "this should be enclave url",
    };

    generatorData = {
      name: "some custom name for the generator",
    };

    const riscZeroVerifier = await new RiscZeroGroth16Verifier__factory(admin).deploy(
      "0x8b6dcf11d463ac455361b41fb3ed053febb817491bdea00fdb340e45013b852e",
      "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e",
    );

    const riscZeroVerifierEmergencyStop = await new RiscZeroVerifierEmergencyStop__factory(admin).deploy(
      await riscZeroVerifier.getAddress(),
      await admin.getAddress(),
    );

    const attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(await riscZeroVerifierEmergencyStop.getAddress());

    const risc0AttestationVerifierWrapper = await new Risc0_attestation_verifier_wrapper__factory(admin).deploy(
      await attestationVerifierZK.getAddress(),
      inputBytes,
      proofBytes,
    );
    iverifier = IVerifier__factory.connect(await risc0AttestationVerifierWrapper.getAddress(), admin);

    let treasuryAddress = await treasury.getAddress();
    await treasury.sendTransaction({ to: matchingEngineEnclave.getAddress(), value: "1000000000000000000" });

    let data = await setup.rawSetup(
      admin,
      tokenHolder,
      totalTokenSupply,
      generatorStakingAmount,
      generatorSlashingPenalty,
      treasuryAddress,
      marketCreationCost,
      marketCreator,
      marketDataToBytes(marketSetupData),
      marketSetupData.inputOuputVerifierUrl,
      iverifier,
      generator,
      generatorDataToBytes(generatorData),
      ivsEnclave,
      matchingEngineEnclave,
      generatorEnclave,
      minRewardByGenerator,
      generatorComputeAllocation,
      computeGivenToNewMarket,
      godEnclave,
    );
    proofMarketplace = data.proofMarketplace;
    generatorRegistry = data.generatorRegistry;
    tokenToUse = data.mockToken;
    priorityLog = data.priorityLog;
    errorLibrary = data.errorLibrary;
    entityKeyRegistry = data.entityKeyRegistry;

    marketId = new BigNumber((await proofMarketplace.marketCounter()).toString()).minus(1).toFixed();

    let marketActivationDelay = await proofMarketplace.MARKET_ACTIVATION_DELAY();
    await skipBlocks(ethers, new BigNumber(marketActivationDelay.toString()).toNumber());
  });

  it("Check risc0 attestation zk verifier", async () => {
    const latestBlock = await ethers.provider.getBlockNumber();

    let assignmentExpiry = 100; // in blocks
    let timeTakenForProofGeneration = 100000000; // keep a large number, but only for tests
    let maxTimeForProofGeneration = 10000; // in blocks

    console.log("Trying to create ask");
    const askId = await setup.createAsk(
      prover,
      tokenHolder,
      {
        marketId,
        proverData: inputBytes,
        reward: rewardForProofGeneration.toFixed(),
        expiry: assignmentExpiry + latestBlock,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      },
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      1,
    );

    await setup.createTask(
      matchingEngineEnclave,
      admin.provider,
      {
        mockToken: tokenToUse,
        proofMarketplace,
        generatorRegistry,
        priorityLog,
        errorLibrary,
        entityKeyRegistry,
      },
      askId,
      generator,
    );

    await expect(proofMarketplace.submitProof(askId, proofBytes)).to.emit(proofMarketplace, "ProofCreated").withArgs(askId, proofBytes);
  });
});
