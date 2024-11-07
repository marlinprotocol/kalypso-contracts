import { ethers } from "hardhat";
import { expect } from "chai";
import { AbiCoder, Signer, ZeroAddress } from "ethers";
import * as attestation4533 from "../helpers/sample/risc0/attestation.json";
import * as attestation4534 from "../helpers/sample/risc0/attestation4534.json";

import {
  RiscZeroGroth16Verifier__factory,
  RiscZeroVerifierEmergencyStop,
  RiscZeroVerifierEmergencyStop__factory,
  AttestationVerifierZK,
  AttestationVerifierZK__factory,
  IRiscZeroVerifierRouter__factory,
} from "../typechain-types";

describe("Attestation verifier for RISC0, testing", () => {
  let signers: Signer[];
  let admin: Signer;

  let attestationVerifierZK: AttestationVerifierZK;
  // let riscZeroVerifier: RiscZeroGroth16Verifier;

  let riscZeroVerifierEmergencyStop: RiscZeroVerifierEmergencyStop;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];

    //Hardhat
    const riscZeroVerifier = await new RiscZeroGroth16Verifier__factory(admin).deploy(
      "0x8b6dcf11d463ac455361b41fb3ed053febb817491bdea00fdb340e45013b852e",
      "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e",
    );

    riscZeroVerifierEmergencyStop = await new RiscZeroVerifierEmergencyStop__factory(admin).deploy(
      await riscZeroVerifier.getAddress(),
      await admin.getAddress(),
    );

    const _attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(await riscZeroVerifierEmergencyStop.getAddress());
    attestationVerifierZK = AttestationVerifierZK__factory.connect(await _attestationVerifierZK.getAddress(), admin);
    expect(attestationVerifierZK.getAddress()).to.not.eq(ZeroAddress);
  });

  it("Check verification on hardhat (4533 bytes)", async () => {
    let seal =
      "0x50bd17690fc93a31b96581f52f239398df9371f74911ab5e3d091635c64ec45984581cc61ac09b9dcc49da498801f6632b2bfd649d5233bb1cf11d9929c56aeca407449824612d2f596e36fa8f11a5f0403879582405cd079ab951c21820e75e6f16101b2b5cea06f6a903713ec4eb861aae32067b055de7ec1a498e9b44a472034ba3290e1ba95be9da41a533b7c8ebabdc87bc3a72d535d0963bc3576513337f26afca0358f2d9bb51e871bb479a0f358c4d13de21c8072b6ef2cc5adfa5adb87b4b0a2f94687025f3bd85b8d8d1e46919460f809348f0b11158990f2eda157b75ed1f26b3d1101276adec9085a4095110de700739128c4ae320a72e5d38d5d6eee755";
    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    // let journal_digest = "0xcd1b9da17add2f43e4feffed585dc72e07ebba44f7e10662630d986e1317e9dc";
    let journal_bytes =
      "0x00000192bd6ad011189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a65d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd166c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb0000";

    const type_input = ["bytes", "bytes32", "bytes"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal_bytes]);
    // console.log({ proofBytes });

    let attestation_object = attestation4533.attestation;
    const types = ["bytes", "bytes"];
    let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
    // console.log({ verification_bytes });

    await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;
    // await expect(riscZeroVerifierEmergencyStop.verify(seal, imageId, journal_digest)).to.not.reverted;
  });

  it("Check verification on hardhat (4534 bytes)", async () => {
    let seal =
      "0x50bd17692b4b54e199336d39bde27d3db67b92550bd571e4c10e64e5b381a96e0ff3ce16273472f1c6535332870ca2449536cb137bf3d39c4e13df2c8a80d1e6bdcd1d9a20680e6b8e5ab136100d18a88165c538cf59511439119cefeb8c428d0a24491a0f4059d98620a9316742dd1830fcade4d36d62f502e8aadf1a3ee22db617f26c1df89b71df8ea83b337f0cf7def14082bd9eeaf5244acce9dadc0c350796b9f8290206e7c1df9aa9e1dcce16f8712188d1a4f97466192bff01001adae4da51932051a82262644a6243fcd18ad855076a8b940a1cb6cf78f9c9791f8b9ed7c98d250d87c1580c39800325f1c90e17328046e4b9918d7cf522998590eb581159e2";
    let imageId = "0x785ecdc7494dcdb0ee09574ad5554c79d8c6b99e8cb11dba5cf3c05a0e71d9ec";
    // let journal_digest = "0x1a7581588b40646c7d8e38aaf0dbccf21a39f0c12c7adfd3159595936a893eae";
    let journal_bytes =
      "0x000001930563c15a189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a65d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd166c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb0000";

    const type_input = ["bytes", "bytes32", "bytes"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal_bytes]);
    // console.log({ proofBytes });

    let attestation_object = attestation4534.attestation;
    const types = ["bytes", "bytes"];
    let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
    // console.log({ verification_bytes });

    // await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;
    await attestationVerifierZK["verify(bytes)"](verification_bytes);
    // await expect(riscZeroVerifierEmergencyStop.verify(seal, imageId, journal_digest)).to.not.reverted;
  });

  it("Check verification on mainnet (4533 bytes)", async () => {
    let seal =
      "0x50bd17690fc93a31b96581f52f239398df9371f74911ab5e3d091635c64ec45984581cc61ac09b9dcc49da498801f6632b2bfd649d5233bb1cf11d9929c56aeca407449824612d2f596e36fa8f11a5f0403879582405cd079ab951c21820e75e6f16101b2b5cea06f6a903713ec4eb861aae32067b055de7ec1a498e9b44a472034ba3290e1ba95be9da41a533b7c8ebabdc87bc3a72d535d0963bc3576513337f26afca0358f2d9bb51e871bb479a0f358c4d13de21c8072b6ef2cc5adfa5adb87b4b0a2f94687025f3bd85b8d8d1e46919460f809348f0b11158990f2eda157b75ed1f26b3d1101276adec9085a4095110de700739128c4ae320a72e5d38d5d6eee755";
    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    let journal_digest = "0xcd1b9da17add2f43e4feffed585dc72e07ebba44f7e10662630d986e1317e9dc";

    const provider = new ethers.JsonRpcProvider("https://eth.llamarpc.com");
    let riscZeroVerifierRouter = IRiscZeroVerifierRouter__factory.connect("0x8EaB2D97Dfce405A1692a21b3ff3A172d593D319", provider);

    await expect(riscZeroVerifierRouter.verify(seal, imageId, journal_digest)).to.not.reverted;
  });

  it("Check verification on mainnet (4534 bytes)", async () => {
    let seal =
      "0x50bd17692b4b54e199336d39bde27d3db67b92550bd571e4c10e64e5b381a96e0ff3ce16273472f1c6535332870ca2449536cb137bf3d39c4e13df2c8a80d1e6bdcd1d9a20680e6b8e5ab136100d18a88165c538cf59511439119cefeb8c428d0a24491a0f4059d98620a9316742dd1830fcade4d36d62f502e8aadf1a3ee22db617f26c1df89b71df8ea83b337f0cf7def14082bd9eeaf5244acce9dadc0c350796b9f8290206e7c1df9aa9e1dcce16f8712188d1a4f97466192bff01001adae4da51932051a82262644a6243fcd18ad855076a8b940a1cb6cf78f9c9791f8b9ed7c98d250d87c1580c39800325f1c90e17328046e4b9918d7cf522998590eb581159e2";
    let imageId = "0x785ecdc7494dcdb0ee09574ad5554c79d8c6b99e8cb11dba5cf3c05a0e71d9ec";
    let journal_digest = "0x1a7581588b40646c7d8e38aaf0dbccf21a39f0c12c7adfd3159595936a893eae";

    const provider = new ethers.JsonRpcProvider("https://eth.llamarpc.com");
    let riscZeroVerifierRouter = IRiscZeroVerifierRouter__factory.connect("0x8EaB2D97Dfce405A1692a21b3ff3A172d593D319", provider);

    await expect(riscZeroVerifierRouter.verify(seal, imageId, journal_digest)).to.not.reverted;
  });
});
