import {
  run,
  tenderly,
} from 'hardhat';

import { getConfig } from '../helper';

const verifyContract = async (contractName: string, isProxy: boolean = false, constructorArguments: any[] = []) => {
  const { addresses } = await getConfig();
  const type = isProxy ? "proxy" : "implementation";
  
  // Verify in Explorer
  try {
    const verificationResult = await run("verify:verify", {
      address: addresses[type][contractName],
      constructorArguments: constructorArguments,
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log(`${contractName} ${type} already verified, continuing...`);
    } else {
      console.error(`Error verifying ${contractName} ${type}:`, error);
    }
  }

  // Verify in Tenderly
  try {
    await tenderly.verify({
      address: addresses[type][contractName],
      name: isProxy ? "ERC1967ProxyFlatten.sol:ERC1967Proxy" : contractName,
    });
  } catch (error) {
    console.error(`Error verifying ${contractName} ${type} on Tenderly:`, error);
  }

  console.log(`(${type}) ${contractName} verified\n`);
}

async function verify(): Promise<string> {
  // StakingManager
  await verifyContract("stakingManager");
  await verifyContract("stakingManager", true);

  // NativeStaking
  await verifyContract("nativeStaking");
  await verifyContract("nativeStaking", true);

  // SymbioticStaking
  await verifyContract("symbioticStaking");
  await verifyContract("symbioticStaking", true);

  // SymbioticStakingReward
  await verifyContract("symbioticStakingReward");
  await verifyContract("symbioticStakingReward", true);

  // ProverManager
  await verifyContract("proverManager");
  await verifyContract("proverManager", true);

  // EntityKeyRegistry
  await verifyContract("entityKeyRegistry");

  // ProofMarketplace
  await verifyContract("proofMarketplace");
  await verifyContract("proofMarketplace", true);

  return "Verify Done";
}

verify().then(console.log).catch(console.error);

