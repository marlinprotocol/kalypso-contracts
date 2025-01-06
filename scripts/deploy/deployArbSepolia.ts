import * as fs from "fs";
import { ethers, upgrades, run } from "hardhat";

import { getConfig } from "../helper";
import { checkFileExists } from "../../helpers";
import {
  AttestationVerifier__factory,
  EntityKeyRegistry__factory,
  NativeStaking__factory,
  ProofMarketplace__factory,
  ProverManager__factory,
  StakingManager__factory,
  SymbioticStaking__factory,
  SymbioticStakingReward__factory,
} from "../../typechain-types";

async function deploy(): Promise<string> {
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
  addresses.implementation.stakingManager = await upgrades.erc1967.getImplementationAddress(addresses.proxy.stakingManager);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("StakingManager deployed at:\t\t", addresses.proxy.stakingManager);

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
  console.log("NativeStaking deployed at:\t\t", addresses.proxy.nativeStaking);

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
  console.log("SymbioticStaking deployed at:\t\t", addresses.proxy.symbioticStaking);

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
  console.log("SymbioticStakingReward deployed at:\t\t", addresses.proxy.symbioticStakingReward);

  // Attestation Verifier
  // TODO: check wether to use existing address or not
  const attestationVerifier = AttestationVerifier__factory.connect(addresses.proxy.attestationVerifier, admin);
  addresses.implementation.attestationVerifier = await upgrades.erc1967.getImplementationAddress(addresses.proxy.attestationVerifier);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // Entity Key Registry
  // TODO: check wether to use existing address or not
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, admin);
  addresses.implementation.entityKeyRegistry = await upgrades.erc1967.getImplementationAddress(addresses.proxy.entityKeyRegistry);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");

  // ProverManager
  const ProverManagerContract = await ethers.getContractFactory("ProverManager");
  const proverProxy = await upgrades.deployProxy(ProverManagerContract, [], {
    kind: "uups",
    initializer: false,
  });
  const proverManager = ProverManager__factory.connect(await proverProxy.getAddress(), admin);
  addresses.proxy.proverManager = await proverManager.getAddress();
  addresses.implementation.proverManager = await upgrades.erc1967.getImplementationAddress(addresses.proxy.proverManager);
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("ProverManager deployed at:\t\t", addresses.proxy.proverManager);

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
  console.log("ProofMarketplace deployed at:\t\t", addresses.proxy.proofMarketplace);

  //---------------------------------------- Initialize ----------------------------------------//

  const mockUSDC = addresses.mockToken.usdc;

  // Staking Manager
  await stakingManager.initialize(
    await admin.getAddress(),
    await proofMarketplace.getAddress(),
    await symbioticStaking.getAddress(),
    await mockUSDC,
  );

  // Native Staking
  const WITHDRAWAL_DURATION = 2 * 60 * 60; // 2 hours
  await nativeStaking.initialize(await admin.getAddress(), await stakingManager.getAddress(), WITHDRAWAL_DURATION, await mockUSDC);

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

  return "Deploy Done";

  //---------------------------------------- Initialize ----------------------------------------//
  // TODO: set address for roles
}

deploy().then(console.log).catch(console.error);
verify().then(console.log).catch(console.error);