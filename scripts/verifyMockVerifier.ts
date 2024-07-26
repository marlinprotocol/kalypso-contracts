import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  let treasury = signers[2];

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  let verificationResult;

  verificationResult = await run("verify:verify", {
    address: "0xABBF9E6674e741656D718431B275EB2c951Aa184",
    constructorArguments: [],
  });
  console.log({ verificationResult });

  return "String";
}

main().then(console.log);
