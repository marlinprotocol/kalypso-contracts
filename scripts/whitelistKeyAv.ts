import { ethers } from "hardhat";
import * as fs from "fs";

import { AttestationVerifier__factory } from "../typechain-types";
import { MockEnclave, MockGeneratorPCRS, MockIVSPCRS, checkFileExists } from "../helpers";

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

  const address = "0x0C0C472801Cc624815874C01383F824805c5d4Bd";

  console.log({ address });

  const attestation_verifier = AttestationVerifier__factory.connect(addresses.proxy.attestation_verifier, admin);

  const mockEnclave = new MockEnclave([MockIVSPCRS[0], MockGeneratorPCRS[1], MockIVSPCRS[2]]);
  try {
    let tx = await attestation_verifier.whitelistImage(MockIVSPCRS[0], MockGeneratorPCRS[1], MockIVSPCRS[2]);
    let receipt = await tx.wait();
    console.log(receipt?.hash);
  } catch (ex) {
    console.log(ex);
  }

  try {
    let tx = await attestation_verifier.whitelistEnclave(mockEnclave.getImageId(), address);
    let receipt = await tx.wait();
    console.log(receipt?.hash);
  } catch (ex) {
    console.log(ex);
  }

  return "Done";
}

main().then(console.log).catch(console.log);
