// import { ethers } from "hardhat";
// import { checkFileExists, hexStringToMarketData } from "../helpers";

// import * as fs from "fs";
// import { ProofMarketPlace__factory } from "../typechain-types";

// async function main(): Promise<string> {
//   const chainId = (await ethers.provider.getNetwork()).chainId.toString();
//   console.log("deploying on chain id:", chainId);

//   const path = `./addresses/${chainId}.json`;
//   const addressesExists = checkFileExists(path);

//   if (!addressesExists) {
//     throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
//   }

//   let signers = await ethers.getSigners();
//   let admin = signers[0];

//   let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

//   const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, admin);

//   const marketIdsToRead = [addresses.zkbMarketId];

//   for (let index = 0; index < marketIdsToRead.length; index++) {
//     const marketId = marketIdsToRead[index];
//     const marketDataBytes = (await proof_market_place.marketData(marketId)).marketmetadata;
//     const marketData = hexStringToMarketData(marketDataBytes);
//     console.log("******* start market data *******");
//     console.log(marketData);
//     console.log("******* end market data *******");
//   }
//   return "Done";
// }

// main().then(console.log).catch(console.log);
