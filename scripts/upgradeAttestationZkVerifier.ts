import { ethers, upgrades, run } from "hardhat";
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
  let attestation_zk_verifier = addresses.proxy.attestation_zk_verifier;

  const AttestationVerifierZK = await ethers.getContractFactory("AttestationVerifierZK");

  const attestationVerifierZk = AttestationVerifierZK__factory.connect(attestation_zk_verifier, admin);

  // using same old verifier patches in attestationVerifierZk
  await upgrades.upgradeProxy(attestation_zk_verifier, AttestationVerifierZK, {
    kind: "uups",
    constructorArgs: [await attestationVerifierZk.RISC0_VERIFIER()],
  });

  return "Upgraded AttestationVerifierZK";
}

main().then(console.log).catch(console.log);
