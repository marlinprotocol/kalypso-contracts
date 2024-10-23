import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { BytesLike, Signer, ZeroAddress } from "ethers";
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

describe("Attestation verifier for RISC0, testing", () => {
    let signers: Signer[];
    let admin: Signer;

    let attestationVerifierZK: AttestationVerifierZK;
    let riscZeroVerifier: RiscZeroGroth16Verifier;

    beforeEach(async () => {
        signers = await ethers.getSigners();
        admin = signers[0];

        //arbSepolia
        // // https://dev.risczero.com/api/blockchain-integration/contracts/verifier#arbitrum-sepolia-421614
        // // control_id 0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e
        // // control_root_0 0x3f05edb31fb4615345ac63d411cf6d8b
        // // control_root_1 0x2e853b01450e34db0fa0de1b4917b8eb
        // // 0xbDB8F2Cc624625B80FCCaBEF04BC5420eF232dfB
        // riscZeroVerifier = RiscZeroGroth16Verifier__factory.connect('0x84b943E31e7fAe6072ce5F75eb4694C7D5F9b0cF');
        // const _attestattionVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(
        //     await riscZeroVerifier.getAddress()
        // );
        // attestationVerifierZK = AttestationVerifierZK__factory.connect(await _attestattionVerifierZK.getAddress(), admin);
        // console.log("Contract address", await attestationVerifierZK.getAddress());
        // expect(attestationVerifierZK.getAddress()).to.not.eq(ZeroAddress);

        //Hardhat
        riscZeroVerifier = await new RiscZeroGroth16Verifier__factory(admin).deploy(
          "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e",
          "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e"
        );
        const attestationVerifierZKContract = await ethers.getContractFactory("AttestationVerifierZK");
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

        const encoded = abiCoder.encode(["string", "string", "string"], [seal, guest_id, journal]);
        const digest = ethers.keccak256(encoded);
        const signature = await admin.signMessage(ethers.getBytes(digest));

        // let key = abiCoder.encode(["uint256[64]"], [attestation.enclavePubKey]);
        // console.log("key: ", key);
        // let pcr0 = abiCoder.encode(["uint256[48]"], [attestation.PCR0]);
        // console.log("pcr0: ", pcr0);
        // let pcr1 = abiCoder.encode(["uint256[48]"], [attestation.PCR1]);
        // console.log("pcr1: ", pcr1);
        // let pcr2 = abiCoder.encode(["uint256[48]"], [attestation.PCR2]);
        // console.log("pcr2: ", pcr2);
        // let ts = abiCoder.encode(["uint256[8]"], [attestation.timestampInMilliseconds]);
        // let time_ts = abiCoder.decode(["uint256"], ts);
        // console.log("ts: ", time_ts);
        let input: IAttestationVerifier.AttestationStruct = {
          enclavePubKey: attestation.enclavePubKey,
          PCR0: attestation.PCR0,
          PCR1: attestation.PCR1,
          PCR2: attestation.PCR2,
          timestampInMilliseconds: attestation.timestampInMilliseconds
        };
        
        let checker = await attestationVerifierZK.getFunction("verify(bytes,(bytes,bytes,bytes,bytes,uint256))").call("attestationVerifierZK", signature, input);
        console.log("Checker: ", checker);
    });
});