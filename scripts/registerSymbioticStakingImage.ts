import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";
import { SymbioticStaking__factory } from "../typechain-types";
import { expect } from "chai";
import { BytesLike } from "ethers";
import { config } from "./config";



async function main() {

  const { chainId, signers, addresses } = await config();

  const admin = signers[0];

  // Symbiotic Staking contract
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbiotic_staking, admin);

  /* Remove Image */

  // Remove Image
  const OLD_PCR0 = "0xe74b4ac0423dea145795651690c7fae34179e15ceaad26cf4664ccbe0dc6faf1740ee81a5431182bd2e5514c9215aba9" as BytesLike;
  const OLD_PCR1 = "0xbcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63f" as BytesLike;
  const OLD_PCR2 = "0x3c753e19f2c242ff601df40dad9ebd5913752133d570faa653e5d8e3118ffe0460cfa43d98b1169c051002a8385e1162" as BytesLike;

  let tx = await symbioticStaking.removeEnclaveImage(await symbioticStaking.getImageId(OLD_PCR0, OLD_PCR1, OLD_PCR2));
  tx.wait();

  /* Add New Image */
  const NEW_PCR0 = "0x3030f7cec2ac000c4ef4513d8b6bf627c246dfdb7d9771595946ab7401fc2a9c8558f15790fb64d0877d189774cafa57" as BytesLike;
  const NEW_PCR1 = "0xbcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63f" as BytesLike;
  const NEW_PCR2 = "0xa72f37d921d94868ffeb4e36f77c15032b5e148b0fa17b08fb1db942850e6d4ec5c012e322a0810aba24fb2d1b2cb0c8" as BytesLike;

  tx = await symbioticStaking.addEnclaveImage(NEW_PCR0, NEW_PCR1, NEW_PCR2);
  tx.wait();
  console.log("Enclave image added");

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
