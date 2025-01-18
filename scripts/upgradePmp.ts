import { ethers, upgrades, run } from "hardhat";
import * as fs from "fs";


import { checkFileExists } from "../helpers";


async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const path = `./addresses/${chainId}.json`;

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  let proof_market_place = addresses.proxy.proof_market_place;

  const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");

//   await upgrades.forceImport(proof_market_place, ProofMarketplace, {
//     kind: "uups",
//   });

  await upgrades.upgradeProxy(proof_market_place, ProofMarketplace, {
    kind: "uups",
    constructorArgs: [],
    redeployImplementation: "always"
  });

  return "Upgraded ProofMarketplace";
}

main().then(console.log).catch(console.log);