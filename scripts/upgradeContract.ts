import {
  ethers,
  run,
} from 'hardhat';

import {
  ProofMarketplace__factory,
  ProverRegistry__factory,
  UUPSUpgradeable__factory,
} from '../typechain-types';
import { config } from './helper';

async function main() {
  const { chainId, signers, addresses } = await config();

  const admin = signers[0];

  // ProofMarketplace Proxy
  const proofMarketplaceProxy = UUPSUpgradeable__factory.connect(addresses.proxy.proof_market_place, admin);

  console.log(    addresses.token.usdc,
    ethers.parseEther("100"),
    addresses.wallet.admin,
    addresses.proxy.prover_registry,
    addresses.proxy.entity_key_registry
  );

  // New Proof Marketplace Implementation
  const newProofMarketplaceImpl = await new ProofMarketplace__factory(admin).deploy(
    addresses.token.usdc,
    ethers.parseEther("100"),
    addresses.wallet.admin,
    addresses.proxy.prover_registry,
    addresses.proxy.entity_key_registry
  );
  await newProofMarketplaceImpl.waitForDeployment();

  // Upgrade Proof Marketplace
  let tx = await proofMarketplaceProxy.upgradeToAndCall(await newProofMarketplaceImpl.getAddress(), "0x");
  await tx.wait();

  console.log("Proof Marketplace upgraded");

  // Prover Registry Proxy
  const proverRegistryProxy = UUPSUpgradeable__factory.connect(addresses.proxy.prover_registry, admin);

  // New Prover Registry Implementation
  const newProverRegistryImpl = await new ProverRegistry__factory(admin).deploy(
    addresses.proxy.entity_key_registry,
    addresses.proxy.staking_manager
  );
  await newProverRegistryImpl.waitForDeployment();

  console.log("Prover Registry upgraded");

  // Upgrade Prover Registry
  tx = await proverRegistryProxy.upgradeToAndCall(await newProverRegistryImpl.getAddress(), "0x");
  await tx.wait();

  let verificationResult = await run("verify:verify", {
    address: await newProofMarketplaceImpl.getAddress(),
    constructorArguments: [
      addresses.token.usdc,
      ethers.parseEther("100"),
      addresses.wallet.admin,
      addresses.proxy.prover_registry,
      addresses.proxy.entity_key_registry,
    ],
  });
  console.log({ verificationResult });
  
  verificationResult = await run("verify:verify", {
    address: await newProverRegistryImpl.getAddress(),
    constructorArguments: [addresses.proxy.entity_key_registry, addresses.proxy.staking_manager],
  });
  console.log({ verificationResult });

  return "Done";
}

main().then(console.log);
