import { ethers } from "hardhat";
import * as fs from "fs";

import { MockVerifier__factory } from "../typechain-types";
import { checkFileExists } from "../helpers";

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
  if (!addresses.proxy.mockVerifier) {
    const mockVerifier = await new MockVerifier__factory(admin).deploy();
    await mockVerifier.waitForDeployment();
    addresses.proxy.mock_verifier = await mockVerifier.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }
  return "Added mockVerifier Deployer";
}

main().then(console.log).catch(console.log);
