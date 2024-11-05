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
    console.log("Contract address", await attestationVerifierZK.getAddress());
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
      "0x50bd17690d954bb001bc07b57991a0743c66130148cf17f80e5fe41b5953ddf0cbe2171a0442cc2125dda3aa1f3ceb36fef82de39f79ccf785318ae78d8bc1f320300e6d2b897d80feac11fce9f28b519af3747ea9f9a73aeb906118029dbea3ab23e84d070810fb9e64256756fe3edd7e1982d4b12332d75a92b3d0b77aa93a953a80da276f4eeb8f23f5d158bc43d3a751f301707c1e9852095414e5eaebc240e85f6317661cc86a0222f9e60206ed570e6eda8ad61578791318a2d7b96fdc66fbf343147c09bd1a76e55c15602f95914c8f392515f0cbb88cbe054a43a2262ba471b517030681bc0c320a3676e68ecc683390841b702f99125a96c04d6e9c1819270d";
    let imageId = "0x785ecdc7494dcdb0ee09574ad5554c79d8c6b99e8cb11dba5cf3c05a0e71d9ec";
    // let journal_digest = "0xb0b6b056d262621f1921cb87ed877de8cf083ec9a11eb09218a217c76adea7af";
    let journal_bytes =
      "0x00000192fb7434ff79f30b845cf0fe67f960adc84cdd5e80bcf06a96640acf4dbc393e277ba73782020c16188ad3fd0f60b0121a2f2da968bcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63fc580b951db7b9981bde4ec14d7c1bc8cce2d51b873cdd4a47a34c5d4279163b0928c82bc3410cc405301be66357f3ddd04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e820ad05039fc7b1d4446619aee7e47955a8e52ed7beed96074f2d4b7468db952abd9320609ba0a351ae3720a72cc6d42b5e03bb95ee5ec7f62ea0c0bad0b7560000";

    const type_input = ["bytes", "bytes32", "bytes"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal_bytes]);
    // console.log({ proofBytes });

    let attestation_object = attestation4534.attestation;
    const types = ["bytes", "bytes"];
    let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
    // console.log({ verification_bytes });

    await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;
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
      "0x50bd17690d954bb001bc07b57991a0743c66130148cf17f80e5fe41b5953ddf0cbe2171a0442cc2125dda3aa1f3ceb36fef82de39f79ccf785318ae78d8bc1f320300e6d2b897d80feac11fce9f28b519af3747ea9f9a73aeb906118029dbea3ab23e84d070810fb9e64256756fe3edd7e1982d4b12332d75a92b3d0b77aa93a953a80da276f4eeb8f23f5d158bc43d3a751f301707c1e9852095414e5eaebc240e85f6317661cc86a0222f9e60206ed570e6eda8ad61578791318a2d7b96fdc66fbf343147c09bd1a76e55c15602f95914c8f392515f0cbb88cbe054a43a2262ba471b517030681bc0c320a3676e68ecc683390841b702f99125a96c04d6e9c1819270d";
    let imageId = "0x785ecdc7494dcdb0ee09574ad5554c79d8c6b99e8cb11dba5cf3c05a0e71d9ec";
    let journal_digest = "0xb0b6b056d262621f1921cb87ed877de8cf083ec9a11eb09218a217c76adea7af";

    const provider = new ethers.JsonRpcProvider("https://eth.llamarpc.com");
    let riscZeroVerifierRouter = IRiscZeroVerifierRouter__factory.connect("0x8EaB2D97Dfce405A1692a21b3ff3A172d593D319", provider);

    await expect(riscZeroVerifierRouter.verify(seal, imageId, journal_digest)).to.not.reverted;
  });
});
