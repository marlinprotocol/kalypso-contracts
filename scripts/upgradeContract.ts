import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";
import { ProofMarketplace__factory, SymbioticStaking__factory, UUPSUpgradeable__factory } from "../typechain-types";
import { expect } from "chai";
import { BytesLike } from "ethers";
import { config } from "./config";

async function main() {
  const { chainId, signers, addresses } = await config();

  const admin = signers[0];

  // Original Symbiotic Staking Proxy
  const symbioticStakingProxy = UUPSUpgradeable__factory.connect(addresses.proxy.symbiotic_staking, admin);

  // New Symbiotic Staking Implementation
  const newSymbioticStaking = await new SymbioticStaking__factory(admin).deploy();
  await newSymbioticStaking.waitForDeployment();

  // Upgrade Symbiotic Staking
  const tx = await symbioticStakingProxy.upgradeToAndCall(await newSymbioticStaking.getAddress(), "0x");
  await tx.wait();

  return "Done";
}

main().then(console.log);
