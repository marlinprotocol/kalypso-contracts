import { ethers } from "hardhat";
import { expect } from "chai";
import { AbiCoder, Signer, ZeroAddress } from "ethers";
import * as attestation from "../helpers/sample/risc0/attestation.json";

import {
  RiscZeroGroth16Verifier,
  RiscZeroGroth16Verifier__factory,
  RiscZeroVerifierEmergencyStop,
  RiscZeroVerifierEmergencyStop__factory,
  AttestationVerifierZK,
  AttestationVerifierZK__factory,
} from "../typechain-types";

describe.only("Attestation verifier for RISC0, testing", () => {
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
    )

    const _attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(await riscZeroVerifierEmergencyStop.getAddress());
    attestationVerifierZK = AttestationVerifierZK__factory.connect(await _attestationVerifierZK.getAddress(), admin);
    console.log("Contract address", await attestationVerifierZK.getAddress());
    expect(attestationVerifierZK.getAddress()).to.not.eq(ZeroAddress);
  });

  it("Check verification", async () => {
    let seal =
      "0x267b16f0ce627262171f212cda46987499eee983a26a855384e8badd70230914091f5aec6feb110c66de327ac1d2e53cf0491ef98fe37cf9e1046d42917b3e561d1ca83546c76770594697c4d42168dffa5a8816f121383f0f60e59cb500e124140a8fe3fd3243edea6cec9be40126562694aea4601ea69105c23e4c7c441ad81f6e126978dd7848f8375132e27f0775aba59f61c0e819efd40f0104d30cadef20915d8eb73648712613166f567661cf7c8550f42c0246f5f97baf8869b172a00d6f157356523dcf664716b2278c70020811d67f06d15d3345f3480edeb7e7f800eaf84204a2037e312f5a4c78693e50939470ed9ad512fc42f3c5b1b872f9d6";
    let claimDigest = "0x35a456463643fd270b2a41d2809cef83ebeff225eaffe9fbfe565dc6555dd1e5";
    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    let journal = "0x56a90e0d02e501fc9f28de7f194c6372ecb1ee7c26bdc8df482ec2a77721ccdb";

    // Checking journal bytes conversion: Valid
    let checker = "0x00000192ba459a73189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a65d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd166c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb0000";
    let att = "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000192ba459a7300000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000030189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000305d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000306c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006104fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000";
    // console.log("Checker test: ", sha256(checker));

    const type_input = ["bytes", "bytes32", "bytes"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, checker]);
    console.log("proofBytes ", proofBytes);
    let attestation_object = attestation;

    let att_type = ["tuple(uint256, bytes, bytes, bytes, bytes, bytes, bytes)"];
    // let attestation_check = new AbiCoder().encode(att_type, [[attestation_object.timestampInMilliseconds, attestation_object.PCR0, attestation_object.PCR1, attestation_object.PCR2, attestation_object.rootPubKey, attestation_object.enclavePubKey, attestation_object.user]]);
    let attestation_check = new AbiCoder().decode(att_type, att);
    console.log("Attest got: ", attestation_check);

    const types = [
      "bytes",
      "tuple(bytes enclavePubKey, bytes PCR0, bytes PCR1, bytes PCR2, uint256 timestampInMilliseconds)"
    ];

    let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
    console.log("verification_bytes", verification_bytes);
    // await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;
    await attestationVerifierZK["verify(bytes)"](verification_bytes);
    // await expect(riscZeroVerifier.verify(seal, imageId, journal)).to.not.reverted;
    await riscZeroVerifierEmergencyStop.verify(seal, imageId, journal);
  });
});
