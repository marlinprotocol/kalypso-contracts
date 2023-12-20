import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  let treasury = signers[2];

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  const path = `./addresses/${chainId}.json`;
  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  let verificationResult;
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.generator_registry,
    constructorArguments: [addresses.proxy.staking_token, addresses.proxy.entity_registry],
  });
  console.log({ verificationResult });

  verificationResult = await run("verify:verify", {
    address: addresses.implementation.proof_market_place,
    constructorArguments: [
      addresses.proxy.payment_token,
      addresses.proxy.staking_token,
      config.marketCreationCost,
      await treasury.getAddress(),
      addresses.proxy.generator_registry,
      addresses.proxy.EntityRegistry,
      addresses.proxy.attestation_verifier,
    ],
  });
  console.log({ verificationResult });

  verificationResult = await run("verify:verify", {
    address: addresses.proxy.generator_registry,
  });
  console.log({ verificationResult });

  verificationResult = await run("verify:verify", {
    address: addresses.proxy.proof_market_place,
  });
  console.log({ verificationResult });
  return "String";
}

main().then(console.log);
