import { ethers } from "hardhat";
import { ProofMarketPlace__factory } from "../typechain-types";
import BigNumber from "bignumber.js";

import * as fs from "fs";
import { checkFileExists } from "../helpers";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const path = `./addresses/${chainId}.json`;
  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
  let admin = signers[0];
  let tokenHolder = signers[1];
  let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  let matchingEngine = signers[5];

  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, matchingEngine);

  const askId = 604;
  const generator = "0x027828B38F8d97Bc85243a50501F10dA721d2Fe0";
  const tx = await proofMarketPlace.connect(matchingEngine).assignTask(askId, generator, "0x");
  console.log("assignment transaction", (await tx.wait())?.hash);
  return "Done";
}

main().then(console.log).catch(console.log);
