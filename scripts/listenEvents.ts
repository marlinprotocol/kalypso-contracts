import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { ProofMarketPlace__factory } from "../typechain-types";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  let admin = signers[0];
  let tokenHolder = signers[1];
  // let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  // let matchingEngine = signers[5];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, admin);
  proofMarketPlace.on(proofMarketPlace.filters.AskCreated, (askId) => {
    console.log({ askId });

    proofMarketPlace.listOfAsk(askId).then(console.log).catch(console.log)
  });
  return "Done";
}

main().then(console.log).catch(console.log);
