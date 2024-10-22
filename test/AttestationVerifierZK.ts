import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Signer, ZeroAddress } from "ethers";
import * as receipt from "../helpers/sample/risc0/receipt.json";
import * as attestation from "../helpers/sample/risc0/attestation.json";

import {
    IRiscZeroVerifier,
    IRiscZeroVerifier__factory,
    AttestationVerifierZK,
    AttestationVerifierZK__factory
} from "../typechain-types";

describe("Attestation verifier for RISC0, testing", () => {
    let signers: Signer[];
    let admin: Signer;

    let attestationVerifierZK: AttestationVerifierZK;
    let riscZeroVerifier: IRiscZeroVerifier;

    beforeEach(async () => {
        signers = await ethers.getSigners();
        admin = signers[0];

        // https://dev.risczero.com/api/blockchain-integration/contracts/verifier#arbitrum-sepolia-421614
        riscZeroVerifier = IRiscZeroVerifier__factory.connect('0x84b943E31e7fAe6072ce5F75eb4694C7D5F9b0cF');
        const AttestationVerifierZKContract = await ethers.getContractFactory("AttestationVerifierZK");
        const _attestattionVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(
            await riscZeroVerifier.getAddress()
        );
        attestationVerifierZK = AttestationVerifierZK__factory.connect(await _attestattionVerifierZK.getAddress(), admin);
        console.log("Contract address", await attestationVerifierZK.getAddress());
        expect(attestationVerifierZK.getAddress()).to.not.eq(ZeroAddress);
    });

    it("Should be able to verify the validity of a RISC0 proof", async () => {
        let abiCoder = new ethers.AbiCoder();
        let guest_id = abiCoder.encode(
            ["uint256[8]"],
            [
              [
                receipt.guest_id[0],
                receipt.guest_id[1],
                receipt.guest_id[2],
                receipt.guest_id[3],
                receipt.guest_id[4],
                receipt.guest_id[5],
                receipt.guest_id[6],
                receipt.guest_id[7],
              ],
            ],
          );
        // console.log("guest_id: ", guest_id);

        let seal = abiCoder.encode(["uint256[256]"], [receipt.receit.inner.Groth16.seal]);
        // console.log("seal: ", seal);
        let journal = abiCoder.encode(["uint256[315]"], [receipt.receit.journal.bytes]);
        // console.log("journal: ", journal);

        let attestation_bytes = abiCoder.encode(["uint256[4532]"], [attestation.attest]);
        let attest_struct = abiCoder.decode(["tuple(bytes,bytes,bytes,bytes,uint256)"], attestation_bytes);
        console.log("Attestation: ", attest_struct);

        // let checker = attestationVerifierZK.getFunction("verify(bytes,(bytes,bytes,bytes,bytes,uint256))").staticCall(seal, guest_id, journal);
    });
});