import { ethers } from "hardhat";
import { expect } from "chai";
import { AbiCoder, Signer, ZeroAddress } from "ethers";

import {
  RiscZeroGroth16Verifier__factory,
  RiscZeroVerifierEmergencyStop,
  RiscZeroVerifierEmergencyStop__factory,
  MarlinTEEAttestationVerifier,
  MarlinTEEAttestationVerifier__factory,
  IRiscZeroVerifierRouter__factory,
  Teefetch,
  Teefetch__factory,
} from "../typechain-types";

describe("Attestation verifier for RISC0, testing", () => {
  let signers: Signer[];
  let admin: Signer;

  let marlinTEEAttestationVerifier: MarlinTEEAttestationVerifier;

  let riscZeroVerifierEmergencyStop: RiscZeroVerifierEmergencyStop;
  let teeFetch: Teefetch;

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

    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    let pcr0 = "0x189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a6";
    let pcr1 = "0x5d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd16";
    let pcr2 = "0x6c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa";
    let root_key = "0x04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4";

    const type_input = ["bytes", "bytes", "bytes"];
    let pcr_bytes = new AbiCoder().encode(type_input, [pcr0, pcr1, pcr2]);
    console.log({ pcr_bytes });

    teeFetch = await new Teefetch__factory(admin).deploy(
        await riscZeroVerifierEmergencyStop.getAddress(), 
        imageId, 
        pcr_bytes, 
        root_key
    );

    const _marlinTEEAttestationVerifier = await new MarlinTEEAttestationVerifier__factory(admin).deploy(await teeFetch.getAddress());
    marlinTEEAttestationVerifier = MarlinTEEAttestationVerifier__factory.connect(await _marlinTEEAttestationVerifier.getAddress(), admin);
    expect(marlinTEEAttestationVerifier.getAddress()).to.not.eq(ZeroAddress);
  });

  it("Check verification & enroll", async () => {
    let seal =
      "0x50bd17690fc93a31b96581f52f239398df9371f74911ab5e3d091635c64ec45984581cc61ac09b9dcc49da498801f6632b2bfd649d5233bb1cf11d9929c56aeca407449824612d2f596e36fa8f11a5f0403879582405cd079ab951c21820e75e6f16101b2b5cea06f6a903713ec4eb861aae32067b055de7ec1a498e9b44a472034ba3290e1ba95be9da41a533b7c8ebabdc87bc3a72d535d0963bc3576513337f26afca0358f2d9bb51e871bb479a0f358c4d13de21c8072b6ef2cc5adfa5adb87b4b0a2f94687025f3bd85b8d8d1e46919460f809348f0b11158990f2eda157b75ed1f26b3d1101276adec9085a4095110de700739128c4ae320a72e5d38d5d6eee755";
    let pubkey = "0xe646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb";
    let timestamp = 1729754746897;
    const type_input = ["bytes", "bytes", "uint64"];
    let dataBytes = new AbiCoder().encode(type_input, [pubkey, seal, timestamp]);
    console.log({ dataBytes });

    await expect(marlinTEEAttestationVerifier["verify(bytes)"](dataBytes)).to.not.reverted;
  });

  it("Check verification on mainnet", async () => {
    let seal =
      "0x50bd17690fc93a31b96581f52f239398df9371f74911ab5e3d091635c64ec45984581cc61ac09b9dcc49da498801f6632b2bfd649d5233bb1cf11d9929c56aeca407449824612d2f596e36fa8f11a5f0403879582405cd079ab951c21820e75e6f16101b2b5cea06f6a903713ec4eb861aae32067b055de7ec1a498e9b44a472034ba3290e1ba95be9da41a533b7c8ebabdc87bc3a72d535d0963bc3576513337f26afca0358f2d9bb51e871bb479a0f358c4d13de21c8072b6ef2cc5adfa5adb87b4b0a2f94687025f3bd85b8d8d1e46919460f809348f0b11158990f2eda157b75ed1f26b3d1101276adec9085a4095110de700739128c4ae320a72e5d38d5d6eee755";
    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    let journal_digest = "0xcd1b9da17add2f43e4feffed585dc72e07ebba44f7e10662630d986e1317e9dc";

    const provider = new ethers.JsonRpcProvider("https://eth.llamarpc.com");
    let riscZeroVerifierRouter = IRiscZeroVerifierRouter__factory.connect("0x8EaB2D97Dfce405A1692a21b3ff3A172d593D319", provider);

    await expect(riscZeroVerifierRouter.verify(seal, imageId, journal_digest)).to.not.reverted;
  });

});
