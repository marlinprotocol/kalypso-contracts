import {
  run,
  tenderly,
} from 'hardhat';
import * as fs from "fs";
import {
  ProofMarketplace__factory,
  UUPSUpgradeable__factory,
} from '../../typechain-types';
import { getConfig } from '../helper';

async function main() {
  const { chainId, signers, path, addresses } = await getConfig();

  const admin = signers[0];

  // // ProofMarketplace Proxy
  // const proofMarketplaceProxy = UUPSUpgradeable__factory.connect(addresses.proxy.proofMarketplace, admin);
  // // New ProofMarketplace Implementation
  // const newProofMarketplaceImpl = await new ProofMarketplace__factory(admin).deploy();
  // await newProofMarketplaceImpl.waitForDeployment();
  
  // addresses.implementation.proofMarketplace = await newProofMarketplaceImpl.getAddress();
  // fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  // console.log("ProofMarketplace deployed at:\t\t", await newProofMarketplaceImpl.getAddress());
  
  // let tx = await proofMarketplaceProxy.upgradeToAndCall(await newProofMarketplaceImpl.getAddress(), "0x");
  // // Upgrade ProofMarketplace
  // await tx.wait();
  // console.log("ProofMarketplace upgraded");
  
  // let verificationResult;
  
  // try {
  //   verificationResult = await run("verify:verify", {
  //     address: await newProofMarketplaceImpl.getAddress(),
  //   });
  //   console.log({ verificationResult });  
  // } catch (error) {
  //   console.error("Error verifying ProofMarketplace implementation on Etherscan:", error);
  // }

  // try {
  //   await tenderly.verify({
  //     address: addresses.implementation.proofMarketplace,
  //     name: "ProofMarketplace",
  //   });
  // } catch (error) {
  //   console.error("Error verifying ProofMarketplace implementation on Tenderly:", error);
  // }

  // ProverManager Proxy
  const proverManagerProxy = UUPSUpgradeable__factory.connect(addresses.proxy.proverManager, admin);
  // New ProverManager Implementation
  const newProverManagerImpl = await new ProverManager__factory(admin).deploy();
  await newProverManagerImpl.waitForDeployment();
  
  addresses.implementation.proverManager = await newProverManagerImpl.getAddress();
  fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("ProverManager deployed at:\t\t", await newProverManagerImpl.getAddress());
  
  // Upgrade ProverManager
  tx = await proverManagerProxy.upgradeToAndCall(await newProverManagerImpl.getAddress(), "0x");
  await tx.wait();
  console.log("ProverManager upgraded");

  try {
    verificationResult = await run("verify:verify", {
      address: await newProverManagerImpl.getAddress(),
    });
    console.log({ verificationResult });  
  } catch (error) {
    console.error("Error verifying ProverManager implementation on Etherscan:", error);
  }

  try {
    await tenderly.verify({
      address: await newProverManagerImpl.getAddress(),
      name: "ProverManager",
    });
  } catch (error) {
    console.error("Error verifying ProverManager implementation on Tenderly:", error);
  }
  
  return "Done";
}

main().then(console.log).catch(console.error);