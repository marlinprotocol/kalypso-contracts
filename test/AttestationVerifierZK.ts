import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { AbiCoder, BytesLike, Signer, ZeroAddress, sha256 } from "ethers";
import * as attestation from "../helpers/sample/risc0/attestation.json";

import {
  RiscZeroGroth16Verifier,
  RiscZeroGroth16Verifier__factory,
  AttestationVerifierZK,
  AttestationVerifierZK__factory,
  IAttestationVerifier,
} from "../typechain-types";

describe.only("Attestation verifier for RISC0, testing", () => {
  let signers: Signer[];
  let admin: Signer;

  let attestationVerifierZK: AttestationVerifierZK;
  let riscZeroVerifier: RiscZeroGroth16Verifier;

  beforeEach(async () => {
    signers = await ethers.getSigners();
    admin = signers[0];

    //Hardhat
    riscZeroVerifier = await new RiscZeroGroth16Verifier__factory(admin).deploy(
      "0x8b6dcf11d463ac455361b41fb3ed053febb817491bdea00fdb340e45013b852e",
      "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e",
    );

    const _attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(await riscZeroVerifier.getAddress());
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

    const type_input = ["bytes", "bytes32", "bytes32"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal]);
    console.log("proofBytes ", proofBytes);
    let attestation_object = attestation; // TODO: this attestation imported seems to be wrong(enclave pubkey is 4400 long, which is not possible, also PCRs seems wrong)
    const types = [
      "bytes",
      "tuple(bytes enclavePubKey, bytes PCR0, bytes PCR1, bytes PCR2, uint256 timestampInMilliseconds)"
    ];

    let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
    console.log("verification_bytes", verification_bytes);
    // await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;
    // await expect(riscZeroVerifier.verify(seal, imageId, journal)).to.not.reverted;
    await riscZeroVerifier.verify(seal, imageId, journal);
  });
});
