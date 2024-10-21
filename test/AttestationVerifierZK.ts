import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Signer, ZeroAddress } from "ethers";

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
        const seal = [2, 16, 23, 90, 97, 98, 64, 104, 70, 45, 45, 178, 42, 13, 47, 111, 171, 142, 188, 91, 138, 184, 94, 61, 96, 32, 42, 161, 51, 129, 36, 199, 5, 144, 234, 187, 7, 60, 133, 98, 176, 94, 51, 154, 172, 149, 163, 104, 31, 90, 96, 33, 169, 217, 16, 157, 74, 113, 8, 43, 249, 249, 123, 130, 32, 119, 105, 152, 165, 8, 50, 178, 120, 186, 175, 46, 137, 254, 4, 183, 52, 132, 38, 28, 88, 173, 48, 86, 170, 118, 199, 10, 5, 169, 131, 128, 3, 24, 154, 80, 148, 94, 121, 163, 188, 152, 236, 157, 78, 35, 57, 135, 99, 40, 208, 182, 62, 1, 240, 195, 144, 252, 79, 185, 217, 122, 2, 65, 35, 229, 83, 107, 168, 23, 145, 243, 81, 28, 18, 197, 108, 46, 91, 93, 69, 179, 181, 109, 199, 197, 218, 134, 68, 118, 78, 248, 0, 239, 165, 222, 25, 29, 167, 52, 155, 8, 213, 69, 245, 145, 252, 77, 116, 67, 135, 95, 207, 197, 125, 93, 143, 176, 93, 213, 56, 165, 34, 103, 109, 0, 78, 212, 1, 248, 235, 244, 2, 240, 212, 222, 101, 41, 170, 210, 5, 154, 107, 117, 87, 38, 91, 234, 244, 99, 38, 30, 45, 85, 142, 190, 205, 145, 47, 48, 40, 147, 135, 151, 224, 181, 89, 254, 7, 161, 0, 108, 253, 214, 106, 184, 154, 48, 182, 111, 50, 237, 240, 243, 44, 191, 200, 223, 8, 229, 8, 86];
        const guestId = [1951632318, 140552053, 1123866864, 2682758743, 3927594904, 1498490529, 418026627, 3602883488];
        const journal_bytes = [0, 0, 1, 146, 159, 123, 80, 156, 24, 144, 56, 236, 207, 40, 163, 160, 152, 148, 158, 64, 47, 59, 61, 134, 168, 118, 244, 145, 92, 91, 2, 213, 70, 171, 181, 216, 197, 7, 206, 177, 117, 91, 129, 146, 216, 207, 202, 102, 232, 242, 38, 22, 12, 164, 199, 166, 93, 57, 56, 235, 5, 40, 142, 32, 169, 129, 3, 139, 24, 97, 6, 47, 244, 23, 72, 132, 150, 138, 57, 174, 229, 152, 43, 49, 40, 148, 230, 5, 97, 136, 53, 118, 204, 115, 129, 209, 167, 208, 91, 128, 153, 54, 189, 22, 108, 62, 243, 99, 196, 136, 169, 168, 111, 170, 99, 164, 70, 83, 253, 128, 110, 100, 93, 69, 64, 180, 5, 64, 135, 111, 59, 129, 31, 193, 188, 238, 207, 3, 106, 71, 3, 240, 117, 135, 197, 1, 238, 69, 187, 86, 161, 170, 4, 252, 2, 84, 235, 166, 8, 193, 243, 104, 112, 226, 154, 218, 144, 190, 70, 56, 50, 146, 115, 110, 137, 75, 255, 246, 114, 217, 137, 68, 75, 80, 81, 229, 52, 164, 177, 246, 219, 227, 192, 188, 88, 26, 50, 183, 177, 118, 7, 14, 222, 18, 214, 154, 63, 234, 33, 27, 102, 231, 82, 207, 125, 209, 221, 9, 95, 111, 19, 112, 244, 23, 8, 67, 217, 220, 16, 1, 33, 228, 207, 99, 1, 40, 9, 102, 68, 135, 201, 121, 98, 132, 48, 77, 197, 63, 244, 230, 70, 248, 176, 7, 29, 91, 167, 89, 49, 64, 37, 34, 204, 106, 92, 66, 168, 74, 111, 234, 35, 136, 100, 229, 172, 154, 14, 18, 216, 59, 211, 109, 12, 129, 9, 211, 202, 43, 105, 159, 206, 141, 8, 43, 243, 19, 245, 210, 174, 36, 155, 178, 117, 182, 182, 233, 30, 15, 205, 146, 98, 244, 187, 0, 0];
        // const result = await attestationVerifierZK["verify(bytes,(bytes,bytes,bytes,bytes,uint256))"]
        // const result = await attestationVerifierZK["verify(bytes,(bytes,bytes,bytes,bytes,uint256))"]

    });
});