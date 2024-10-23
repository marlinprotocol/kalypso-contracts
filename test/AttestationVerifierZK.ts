import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { AbiCoder, BytesLike, Signer, ZeroAddress } from "ethers";
import * as receipt from "../helpers/sample/risc0/receipt.json";
// import * as attestation from "../helpers/sample/risc0/attestation.json";
import * as attestation from "../helpers/sample/risc0/final.json";

import {
    RiscZeroGroth16Verifier,
    RiscZeroGroth16Verifier__factory,
    AttestationVerifierZK,
    AttestationVerifierZK__factory,
    IAttestationVerifier
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
          "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e"
        );
      
        const _attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(
          await riscZeroVerifier.getAddress()
        );
        attestationVerifierZK = AttestationVerifierZK__factory.connect(await _attestationVerifierZK.getAddress(), admin);
        console.log("Contract address", await attestationVerifierZK.getAddress());
        expect(attestationVerifierZK.getAddress()).to.not.eq(ZeroAddress);
    });

    it("Check verification", async() => {
      let proofBytes = "0x1234" // TODO: get proof bytes from receipt
      let attestation_object = attestation; // TODO: this attestation imported seems to be wrong(enclave pubkey is 4400 long, which is not possible, also PCRs seems wrong)

      const types = [
        "bytes",
        "tuple(bytes enclavePubKey, bytes PCR0, bytes PCR1, bytes PCR2, uint256 timestampInMilliseconds)"
    ];

      let verification_bytes = new AbiCoder().encode(types, [proofBytes, attestation_object]);
      await expect(attestationVerifierZK["verify(bytes)"](verification_bytes)).to.not.reverted;

    })
});