import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";
import { SymbioticStaking__factory } from "../typechain-types";
import { expect } from "chai";
import { BytesLike } from "ethers";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  console.log(signers);
  const admin = signers[0];

  const path = `./addresses/${chainId}.json`;
  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  // Grant `BRIDGE_ENCLAVE_UPDATES_ROLE` to admin
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbiotic_staking, admin);
  let tx = await symbioticStaking.grantRole(await symbioticStaking.BRIDGE_ENCLAVE_UPDATES_ROLE(), admin.address);
  tx.wait();
  expect(await symbioticStaking.hasRole(await symbioticStaking.BRIDGE_ENCLAVE_UPDATES_ROLE(), admin.address)).to.be.true;

  // Register Image
  const PCR0 = "0x47c52d4a55b4c2a82f6d99b56fe54107c2eb2c6c70ad12435d568d08593a13d7ae452cbf9a31d83838c9f8ec3d099621" as BytesLike;
  const PCR1 = "0xbcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63f" as BytesLike;
  const PCR2 = "0xd0ec892e99dce4cd7b4f461b61d2826bf9b0d7da11a276b5d5632be439bc0c417fced1bd7b80adabafbbd588186a5f53" as BytesLike;

  // tx = await symbioticStaking.addEnclaveImage(PCR0, PCR1, PCR2);
  // tx.wait();
  
  tx = await symbioticStaking.setAttestationVerifier(addresses.proxy.attestation_verifier);
  tx.wait();
  console.log("Attestation verifier set: ", addresses.proxy.attestation_verifier);

  // const configPath = `./config/${chainId}.json`;
  // const configurationExists = checkFileExists(configPath);

  // if (!configurationExists) {
  //   throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  // }

  // const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  // const path = `./addresses/${chainId}.json`;
  // const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  // let verificationResult;

  // console.log({ verificationResult });

  return "Done";
}

main().then(console.log);
