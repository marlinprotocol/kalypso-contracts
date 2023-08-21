import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists, marketDataToBytes } from "../helpers";
import { ProofMarketPlace__factory } from "../typechain-types";

import * as proof from "../data/transferVerifier/1/proof.json";

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

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
  const tokenHolder = signers[1];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses?.proxy?.proofMarketPlace) {
    throw new Error("Proof Market Place Is Not Deployed");
  }
  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, tokenHolder);

  const taskId = 498;

  const taskDetails = await proofMarketPlace.connect(tokenHolder).listOfTask(161);
  console.log(taskDetails);
  const askId = taskDetails.askId;

  const askDetails = await proofMarketPlace.connect(tokenHolder).listOfAsk(askId);
  console.log(askDetails);

  const askState = await proofMarketPlace.connect(tokenHolder).getAskState(askId);
  console.log({ askState });

  let abiCoder = new ethers.AbiCoder();

  let proofBytes = abiCoder.encode(
    ["uint256[8]"],
    [[proof.a[0], proof.a[1], proof.b[0][0], proof.b[0][1], proof.b[1][0], proof.b[1][1], proof.c[0], proof.c[1]]],
  );

  const tx = await proofMarketPlace.connect(tokenHolder).submitProof(taskId, proofBytes);
  const receipt = await tx.wait();
  console.log("receipt hash", receipt?.hash);

  return `${receipt?.hash}`;
}

main().then(console.log).catch(console.log);
