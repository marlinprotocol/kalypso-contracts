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

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  const path = `./addresses/${chainId}.json`;
  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  let verificationResult;

  verificationResult = await run("verify:verify", {
    address: "0xb70cfd05B57a1e9b7E1217d53493C1C4B7cacb98",
    constructorArguments: ["0x7376026b2638829aB4F58B9a1a0801485048A328", "0x63EEf1576b477Aa60Bfd7300B2C85b887639Ac1b"],
  });
  console.log({ verificationResult });

  return "String";
}

main().then(console.log);
