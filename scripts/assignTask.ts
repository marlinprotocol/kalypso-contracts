// import { ethers } from "hardhat";
// import { ProofMarketPlace__factory } from "../typechain-types";

// import * as fs from "fs";
// import { checkFileExists } from "../helpers";

// async function main(): Promise<string> {
//   const chainId = (await ethers.provider.getNetwork()).chainId.toString();
//   console.log("deploying on chain id:", chainId);

//   const signers = await ethers.getSigners();
//   console.log("available signers", signers.length);

//   if (signers.length < 6) {
//     throw new Error("Atleast 6 signers are required for deployment");
//   }

//   const path = `./addresses/${chainId}.json`;
//   const configPath = `./config/${chainId}.json`;
//   const configurationExists = checkFileExists(configPath);

//   if (!configurationExists) {
//     throw new Error(`Config doesn't exists for chainId: ${chainId}`);
//   }

//   const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
//   let admin = signers[0];
//   let tokenHolder = signers[1];
//   let treasury = signers[2];
//   // let marketCreator = signers[3];
//   // let generator = signers[4];
//   let matchingEngine = signers[5];

//   const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
//   const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, matchingEngine);

//   const askId = 2;
//   const generator = "0x01f01074dc5454B15faBf1F1006864D0b71e3f19";
//   const tx = await proof_market_place.connect(matchingEngine).assignTask(askId, generator, "0x");
//   console.log("assignment transaction", (await tx.wait())?.hash);
//   return "Done";
// }

// main().then(console.log).catch(console.log);
