import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { MockToken__factory } from "../typechain-types";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

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

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
  let admin = signers[0];
  let tokenHolder = signers[1];
  let treasury = signers[2];
  let marketCreator = signers[3];
  let generator = signers[4];
  let matchingEngine = signers[5];
  let prover = signers[6];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    throw new Error("token contract not deployed");
  }

  (await admin.sendTransaction({ to: await prover.getAddress(), value: "10000000000000000" })).wait();
  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
  const tx = await mockToken.connect(tokenHolder).transfer(await prover.getAddress(), "10000000000000000000");

  const receipt = await tx.wait();

  return `Done: ${receipt?.hash}`;
}

main().then(console.log).catch(console.log);
