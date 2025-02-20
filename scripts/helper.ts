import * as fs from "fs";
import { ethers } from "hardhat";
import { run } from "hardhat";

export async function getConfig() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log(signers);

  const path = `./addresses/${chainId}.json`;
  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  return { chainId, signers, path, addresses };
}

export async function verify(address: string, constructorArguments: any[]) {
  const verificationResult = await run("verify:verify", {
    address,
    constructorArguments
  });
  console.log({ verificationResult });
}