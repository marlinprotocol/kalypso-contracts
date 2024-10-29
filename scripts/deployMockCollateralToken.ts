import { ethers, run } from "hardhat";
import * as fs from "fs";

import { OpenMintToken__factory } from "../typechain-types";
import { checkFileExists } from "../helpers";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 1) {
    throw new Error("Atleast 1 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  let deployer = signers[1];

  const token = await new OpenMintToken__factory(deployer).deploy();
  await token.waitForDeployment();
  const address = await token.getAddress();

  // wait for 30 seconds for the contract to be deployed
  await new Promise((resolve) => setTimeout(resolve, 30000));

  await run("verify:verify", {
      address,
      constructorArguments: [],
  });

  return "Deployer mock collateral token";
}

main().then(console.log).catch(console.log);
