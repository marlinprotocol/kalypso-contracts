import { ethers, run } from "hardhat";
import * as fs from "fs";

import {
  AttestationVerifierZK__factory,
  Risc0_attestation_verifier_wrapper__factory,
  RiscZeroGroth16Verifier__factory,
  RiscZeroVerifierEmergencyStop__factory,
} from "../typechain-types";
import { checkFileExists } from "../helpers";
import { AbiCoder } from "ethers";
import * as attestation from "../helpers/sample/risc0/attestation.json";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  let admin = signers[0];

  const path = `./addresses/${chainId}.json`;

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.attestation_zk_verifier) {
    const riscZeroVerifier = await new RiscZeroGroth16Verifier__factory(admin).deploy(
      "0x8b6dcf11d463ac455361b41fb3ed053febb817491bdea00fdb340e45013b852e",
      "0x05a022e1db38457fb510bc347b30eb8f8cf3eda95587653d0eac19e1f10d164e",
    );
    await riscZeroVerifier.deploymentTransaction()?.wait(2);

    let riscZeroVerifierEmergencyStop = await new RiscZeroVerifierEmergencyStop__factory(admin).deploy(
      await riscZeroVerifier.getAddress(),
      await admin.getAddress(),
    );
    await riscZeroVerifierEmergencyStop.deploymentTransaction()?.wait(2);

    const attestationVerifierZK = await new AttestationVerifierZK__factory(admin).deploy(await riscZeroVerifierEmergencyStop.getAddress());
    await riscZeroVerifierEmergencyStop.deploymentTransaction()?.wait(2);

    addresses.proxy.attestation_zk_verifier = await attestationVerifierZK.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    await run("verify:verify", {
      address: await attestationVerifierZK.getAddress(),
      constructorArguments: [await riscZeroVerifierEmergencyStop.getAddress()],
    });
  }

  if (!addresses.proxy.attestation_zk_verifier_wrapper) {
    let seal =
      "0x50bd1769267b16f0ce627262171f212cda46987499eee983a26a855384e8badd70230914091f5aec6feb110c66de327ac1d2e53cf0491ef98fe37cf9e1046d42917b3e561d1ca83546c76770594697c4d42168dffa5a8816f121383f0f60e59cb500e124140a8fe3fd3243edea6cec9be40126562694aea4601ea69105c23e4c7c441ad81f6e126978dd7848f8375132e27f0775aba59f61c0e819efd40f0104d30cadef20915d8eb73648712613166f567661cf7c8550f42c0246f5f97baf8869b172a00d6f157356523dcf664716b2278c70020811d67f06d15d3345f3480edeb7e7f800eaf84204a2037e312f5a4c78693e50939470ed9ad512fc42f3c5b1b872f9d6";
    // let claimDigest = "0x35a456463643fd270b2a41d2809cef83ebeff225eaffe9fbfe565dc6555dd1e5";
    let imageId = "0xbe8b537475a76008f0d8fc4257a6e79f98571aeaa12651598394ea18a0a3bfd6";
    let journal_bytes =
      "0x00000192ba459a73189038eccf28a3a098949e402f3b3d86a876f4915c5b02d546abb5d8c507ceb1755b8192d8cfca66e8f226160ca4c7a65d3938eb05288e20a981038b1861062ff4174884968a39aee5982b312894e60561883576cc7381d1a7d05b809936bd166c3ef363c488a9a86faa63a44653fd806e645d4540b40540876f3b811fc1bceecf036a4703f07587c501ee45bb56a1aa04fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4e646f8b0071d5ba75931402522cc6a5c42a84a6fea238864e5ac9a0e12d83bd36d0c8109d3ca2b699fce8d082bf313f5d2ae249bb275b6b6e91e0fcd9262f4bb0000";

    const type_input = ["bytes", "bytes32", "bytes"];
    let proofBytes = new AbiCoder().encode(type_input, [seal, imageId, journal_bytes]);

    let attestation_object = attestation;
    const types = ["tuple(bytes enclavePubKey, bytes PCR0, bytes PCR1, bytes PCR2, uint256 timestampInMilliseconds)"];
    let inputBytes = new AbiCoder().encode(types, [attestation_object]);

    const risc0AttestationVerifierWrapper = await new Risc0_attestation_verifier_wrapper__factory(admin).deploy(
      addresses.proxy.attestation_zk_verifier,
      inputBytes,
      proofBytes,
    );
    await risc0AttestationVerifierWrapper.deploymentTransaction()?.wait(2);

    addresses.proxy.attestation_zk_verifier_wrapper = await risc0AttestationVerifierWrapper.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    await run("verify:verify", {
      address: await risc0AttestationVerifierWrapper.getAddress(),
      constructorArguments: [addresses.proxy.attestation_zk_verifier, inputBytes, proofBytes],
    });
  }
  return "Added Tee Verifier Deployer";
}

main().then(console.log).catch(console.log);
