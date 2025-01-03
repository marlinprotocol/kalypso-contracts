import * as fs from 'fs';
import {
  ethers,
  upgrades,
} from 'hardhat';

import { getConfig } from '../helper';
import { checkFileExists } from '../../helpers';
import { AttestationVerifier__factory, EntityKeyRegistry__factory, NativeStaking__factory, ProofMarketplace__factory, ProverRegistry__factory, StakingManager__factory, SymbioticStaking__factory, SymbioticStakingReward__factory } from '../../typechain-types';

async function main(): Promise<string> {

  const { chainId, signers, addresses } = await getConfig();
  console.log("Deploying on chain id:", chainId);
  
  console.log("Available Signers", signers);
  const admin = signers[0];

  const configPath = `./config/${chainId}.json`;
  const addressPath = `./addresses/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  //---------------------------------------- Deploy ----------------------------------------//
  // Staking Manager
  const StakingManagerContract = await ethers.getContractFactory("StakingManager");
  const stakingManagerProxy = await upgrades.deployProxy(StakingManagerContract, [], {
    kind: "uups",
    initializer: false,
  });
  await stakingManagerProxy.waitForDeployment();
  const stakingManager = StakingManager__factory.connect(await stakingManagerProxy.getAddress(), admin);
  addresses.proxy.stakingManager = await stakingManager.getAddress();
  addresses.implementation.stakingManager = await upgrades.erc1967.getImplementationAddress(addresses.proxy.entity_registry);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Native Staking
  const NativeStakingContract = await ethers.getContractFactory("NativeStaking");
  const nativeStakingProxy = await upgrades.deployProxy(NativeStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const nativeStaking = NativeStaking__factory.connect(await nativeStakingProxy.getAddress(), admin);
  addresses.proxy.nativeStaking = await nativeStaking.getAddress();
  addresses.implementation.nativeStaking = await upgrades.erc1967.getImplementationAddress(addresses.proxy.nativeStaking);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Symbiotic Staking
  const SymbioticStakingContract = await ethers.getContractFactory("SymbioticStaking");
  const symbioticStakingProxy = await upgrades.deployProxy(SymbioticStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const symbioticStaking = SymbioticStaking__factory.connect(await symbioticStakingProxy.getAddress(), admin);
  addresses.proxy.symbioticStaking = await symbioticStaking.getAddress();
  addresses.implementation.symbioticStaking = await upgrades.erc1967.getImplementationAddress(addresses.proxy.symbioticStaking);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Symbiotic Staking Reward
  const SymbioticStakingRewardContract = await ethers.getContractFactory("SymbioticStakingReward");
  const symbioticStakingRewardProxy = await upgrades.deployProxy(SymbioticStakingRewardContract, [], {
    kind: "uups",
    initializer: false,
  });
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(await symbioticStakingRewardProxy.getAddress(), admin);
  addresses.proxy.symbioticStakingReward = await symbioticStakingReward.getAddress();
  addresses.implementation.symbioticStakingReward = await upgrades.erc1967.getImplementationAddress(addresses.proxy.symbioticStakingReward);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Attestation Verifier
  // TODO: check wether to use existing address or not
  const attestationVerifier = AttestationVerifier__factory.connect(addresses.proxy.attestation_verifier, admin);
  addresses.implementation.attestationVerifier = await upgrades.erc1967.getImplementationAddress(addresses.proxy.attestation_verifier);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Entity Key Registry
  // TODO: check wether to use existing address or not
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entity_key_registry, admin);
  addresses.implementation.entityKeyRegistry = await upgrades.erc1967.getImplementationAddress(addresses.proxy.entity_key_registry);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Prover Registry
  const ProverRegistryContract = await ethers.getContractFactory("ProverRegistry");
  const proverProxy = await upgrades.deployProxy(ProverRegistryContract, [], {
    kind: "uups",
    initializer: false,
  });
  const proverRegistry = ProverRegistry__factory.connect(await proverProxy.getAddress(), admin);
  addresses.proxy.proverRegistry = await proverRegistry.getAddress();
  addresses.implementation.proverRegistry = await upgrades.erc1967.getImplementationAddress(addresses.proxy.proverRegistry);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // ProofMarketplace
  const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
  const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
    kind: "uups",
    initializer: false,
  });
  const proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), admin);
  addresses.proxy.proofMarketplace = await proofMarketplace.getAddress();
  addresses.implementation.proofMarketplace = await upgrades.erc1967.getImplementationAddress(addresses.proxy.proofMarketplace);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  
  //---------------------------------------- Initialize ----------------------------------------//

  const mockUSDC = addresses.token.usdc;

  // Staking Manager
  await stakingManager.initialize(
    await admin.getAddress(),
    await proofMarketplace.getAddress(),
    await symbioticStaking.getAddress(),
    await mockUSDC,
  );

  // Native Staking
  const WITHDRAWAL_DURATION = 2 * 60 * 60;
  await nativeStaking.initialize(
    await admin.getAddress(),
    await stakingManager.getAddress(),
    WITHDRAWAL_DURATION,
    await mockUSDC,
  );

  // Symbiotic Staking
  await symbioticStaking.initialize(
    await admin.getAddress(),
    await attestationVerifier.getAddress(),
    await proofMarketplace.getAddress(),
    await stakingManager.getAddress(),
    await symbioticStakingReward.getAddress(),
    await mockUSDC,
  );

  // Symbiotic Staking Reward
  await symbioticStakingReward.initialize(
    await admin.getAddress(),
    await proofMarketplace.getAddress(),
    await symbioticStaking.getAddress(),
    await mockUSDC,
  );

  return "Done";
}

main().then(console.log).catch(console.error);