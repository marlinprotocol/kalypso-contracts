import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";
import { GeneratorRegistry__factory, ProofMarketplace__factory, SymbioticStaking__factory, UUPSUpgradeable__factory } from "../typechain-types";
import { expect } from "chai";
import { BytesLike } from "ethers";
import { config } from "./helper";

async function main() {
  const { chainId, signers, addresses } = await config();

  const admin = signers[0];

  // ProofMarketplace Proxy
  const proofMarketplaceProxy = UUPSUpgradeable__factory.connect(addresses.proxy.proof_market_place, admin);

  console.log(    addresses.token.usdc,
    ethers.parseEther("100"),
    addresses.wallet.admin,
    addresses.proxy.generator_registry,
    addresses.proxy.entity_key_registry
  );

  // New Proof Marketplace Implementation
  const newProofMarketplaceImpl = await new ProofMarketplace__factory(admin).deploy(
    addresses.token.usdc,
    ethers.parseEther("100"),
    addresses.wallet.admin,
    addresses.proxy.generator_registry,
    addresses.proxy.entity_key_registry
  );
  await newProofMarketplaceImpl.waitForDeployment();

  // Upgrade Proof Marketplace
  let tx = await proofMarketplaceProxy.upgradeToAndCall(await newProofMarketplaceImpl.getAddress(), "0x");
  await tx.wait();

  console.log("Proof Marketplace upgraded");

  // Generator Registry Proxy
  const generatorRegistryProxy = UUPSUpgradeable__factory.connect(addresses.proxy.generator_registry, admin);

  // New Generator Registry Implementation
  const newGeneratorRegistryImpl = await new GeneratorRegistry__factory(admin).deploy(
    addresses.proxy.entity_key_registry,
    addresses.proxy.staking_manager
  );
  await newGeneratorRegistryImpl.waitForDeployment();

  console.log("Generator Registry upgraded");

  // Upgrade Generator Registry
  tx = await generatorRegistryProxy.upgradeToAndCall(await newGeneratorRegistryImpl.getAddress(), "0x");
  await tx.wait();

  let verificationResult = await run("verify:verify", {
    address: await newProofMarketplaceImpl.getAddress(),
    constructorArguments: [
      addresses.token.usdc,
      ethers.parseEther("100"),
      addresses.wallet.admin,
      addresses.proxy.generator_registry,
      addresses.proxy.entity_key_registry,
    ],
  });
  console.log({ verificationResult });
  
  verificationResult = await run("verify:verify", {
    address: await newGeneratorRegistryImpl.getAddress(),
    constructorArguments: [addresses.proxy.entity_key_registry, addresses.proxy.staking_manager],
  });
  console.log({ verificationResult });

  return "Done";
}

main().then(console.log);
