import {
  run,
  tenderly,
} from 'hardhat';

import { getConfig } from '../helper';

enum ContractType {
  Proxy = "proxy",
  Implementation = "implementation",
}

const verifyContract = async (contractName: string, contractType: ContractType, constructorArguments: any[] = []) => {
  const { addresses } = await getConfig();
  const isProxy = contractType === ContractType.Proxy;
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
  const { addresses } = await getConfig();
  // StakingManager
  await verifyContract("stakingManager", ContractType.Implementation);
  await verifyContract("stakingManager", ContractType.Proxy);

  // NativeStaking
  await verifyContract("nativeStaking", ContractType.Implementation);
  await verifyContract("nativeStaking", ContractType.Proxy);

  // SymbioticStaking
  await verifyContract("symbioticStaking", ContractType.Implementation);
  await verifyContract("symbioticStaking", ContractType.Proxy);

  // SymbioticStakingReward
  await verifyContract("symbioticStakingReward", ContractType.Implementation);
  await verifyContract("symbioticStakingReward", ContractType.Proxy);

  // ProverManager
  await verifyContract("proverManager", ContractType.Implementation);
  await verifyContract("proverManager", ContractType.Proxy);

  // EntityKeyRegistry
  await verifyContract("entityKeyRegistry", ContractType.Implementation, [addresses.proxy.attestationVerifier]);
  await verifyContract("entityKeyRegistry", ContractType.Proxy);

  // ProofMarketplace
  await verifyContract("proofMarketplace", ContractType.Implementation);
  await verifyContract("proofMarketplace", ContractType.Proxy);

  // AttestationVerifier
  await verifyContract("attestationVerifier", ContractType.Implementation);
  await verifyContract("attestationVerifier", ContractType.Proxy);

  return "Verify Done";
}

verify().then(console.log).catch(console.error);

