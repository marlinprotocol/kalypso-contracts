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
  const deployer = signers[0];

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
  const stakingManager = StakingManager__factory.connect(await stakingManagerProxy.getAddress(), deployer);
  addresses.proxy.stakingManager = await stakingManager.getAddress();
  addresses.implementation.stakingManager = await upgrades.erc1967.getImplementationAddress(await stakingManager.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("StakingManager deployed at:\t\t", await stakingManager.getAddress());

  // Native Staking
  const NativeStakingContract = await ethers.getContractFactory("NativeStaking");
  const nativeStakingProxy = await upgrades.deployProxy(NativeStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const nativeStaking = NativeStaking__factory.connect(await nativeStakingProxy.getAddress(), deployer);
  addresses.proxy.nativeStaking = await nativeStaking.getAddress();
  addresses.implementation.nativeStaking = await upgrades.erc1967.getImplementationAddress(await nativeStaking.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("NativeStaking deployed at:\t\t", await nativeStaking.getAddress());

  // Symbiotic Staking
  const SymbioticStakingContract = await ethers.getContractFactory("SymbioticStaking");
  const symbioticStakingProxy = await upgrades.deployProxy(SymbioticStakingContract, [], {
    kind: "uups",
    initializer: false,
  });
  const symbioticStaking = SymbioticStaking__factory.connect(await symbioticStakingProxy.getAddress(), deployer);
  addresses.proxy.symbioticStaking = await symbioticStaking.getAddress();
  addresses.implementation.symbioticStaking = await upgrades.erc1967.getImplementationAddress(await symbioticStaking.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("SymbioticStaking deployed at:\t\t", await symbioticStaking.getAddress());

  // Symbiotic Staking Reward
  const SymbioticStakingRewardContract = await ethers.getContractFactory("SymbioticStakingReward");
  const symbioticStakingRewardProxy = await upgrades.deployProxy(SymbioticStakingRewardContract, [], {
    kind: "uups",
    initializer: false,
  });
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(await symbioticStakingRewardProxy.getAddress(), deployer);
  addresses.proxy.symbioticStakingReward = await symbioticStakingReward.getAddress();
  addresses.implementation.symbioticStakingReward = await upgrades.erc1967.getImplementationAddress(await symbioticStakingReward.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("SymbioticStakingReward deployed at:\t\t", await symbioticStakingReward.getAddress());

  // Attestation Verifier
  const AttestationVerifierContract = await ethers.getContractFactory("AttestationVerifier");
  const attestationVerifierProxy = await upgrades.deployProxy(AttestationVerifierContract, [], {
    kind: "uups",
    initializer: false,
  });
  const attestationVerifier = AttestationVerifier__factory.connect(await attestationVerifierProxy.getAddress(), deployer);
  addresses.proxy.attestationVerifier = await attestationVerifier.getAddress();
  addresses.implementation.attestationVerifier = await upgrades.erc1967.getImplementationAddress(await attestationVerifier.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("AttestationVerifier deployed at:\t\t", await attestationVerifier.getAddress());

  // Entity Key Registry
  const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
  const entityKeyRegistryProxy = await upgrades.deployProxy(EntityKeyRegistryContract, [], {
    kind: "uups",
    initializer: false,
    constructorArgs: [await attestationVerifier.getAddress()],
  });
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(await entityKeyRegistryProxy.getAddress(), deployer);
  addresses.proxy.entityKeyRegistry = await entityKeyRegistry.getAddress();
  addresses.implementation.entityKeyRegistry = await upgrades.erc1967.getImplementationAddress(await entityKeyRegistry.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("EntityKeyRegistry deployed at:\t\t", await entityKeyRegistry.getAddress());

  // ProverManager
  const ProverManagerContract = await ethers.getContractFactory("ProverManager");
  const proverProxy = await upgrades.deployProxy(ProverManagerContract, [], {
    kind: "uups",
    initializer: false,
  });
  const proverManager = ProverManager__factory.connect(await proverProxy.getAddress(), deployer);
  addresses.proxy.proverManager = await proverManager.getAddress();
  addresses.implementation.proverManager = await upgrades.erc1967.getImplementationAddress(await proverManager.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("ProverManager deployed at:\t\t", await proverManager.getAddress());

  // ProofMarketplace
  const ProofMarketplace = await ethers.getContractFactory("ProofMarketplace");
  const proxy = await upgrades.deployProxy(ProofMarketplace, [], {
    kind: "uups",
    initializer: false,
  });
  const proofMarketplace = ProofMarketplace__factory.connect(await proxy.getAddress(), deployer);
  addresses.proxy.proofMarketplace = await proofMarketplace.getAddress();
  addresses.implementation.proofMarketplace = await upgrades.erc1967.getImplementationAddress(await proofMarketplace.getAddress());
  fs.writeFileSync(addressPath, JSON.stringify(addresses, null, 4), "utf-8");
  console.log("ProofMarketplace deployed at:\t\t", await proofMarketplace.getAddress());

  return "Deploy Done";
  // TODO: set address for roles
}

async function initialize(): Promise<string> {
  const { chainId, signers, addresses } = await getConfig();
  console.log("Initializing on chain id:", chainId);

  console.log("Available Signers", signers);
  
  const deployer = signers[0];

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  //---------------------------------------- Initialize ----------------------------------------//
  const stakingManager = StakingManager__factory.connect(addresses.proxy.stakingManager, deployer);
  const nativeStaking = NativeStaking__factory.connect(addresses.proxy.nativeStaking, deployer);
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbioticStaking, deployer);
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(addresses.proxy.symbioticStakingReward, deployer);
  const attestationVerifier = AttestationVerifier__factory.connect(addresses.proxy.attestationVerifier, deployer);
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, deployer);
  const proverManager = ProverManager__factory.connect(addresses.proxy.proverManager, deployer);
  const proofMarketplace = ProofMarketplace__factory.connect(addresses.proxy.proofMarketplace, deployer);

  const USDC = config.USDC;
  const admin = config.admin;
  const treasury = config.treasury;

  // Staking Manager
  console.log(await stakingManager.hasRole(await symbioticStaking.DEFAULT_ADMIN_ROLE(), admin));
  if(!await stakingManager.hasRole(await symbioticStaking.DEFAULT_ADMIN_ROLE(), admin)) {
    await stakingManager.initialize(
      admin,
      await proofMarketplace.getAddress(),
      await proverManager.getAddress(),
      await symbioticStaking.getAddress(),
      USDC,
    );
    console.log("StakingManager initialized");
  }

  // Native Staking
  // const WITHDRAWAL_DURATION = 2 * 60 * 60; // 2 hours
  const WITHDRAWAL_DURATION = config.staking.native.withdrawalDuration;
  if(!await nativeStaking.hasRole(await nativeStaking.DEFAULT_ADMIN_ROLE(), admin)) {
    await nativeStaking.initialize(admin, await stakingManager.getAddress(), WITHDRAWAL_DURATION);
    console.log("NativeStaking initialized");
  }

  // Symbiotic Staking
  if(!await symbioticStaking.hasRole(await symbioticStaking.DEFAULT_ADMIN_ROLE(), admin)) {
    await symbioticStaking.initialize(
      admin,
      await attestationVerifier.getAddress(),
      await proofMarketplace.getAddress(),
      await stakingManager.getAddress(),
      await symbioticStakingReward.getAddress(),
    );
    console.log("SymbioticStaking initialized");
  }

  // Symbiotic Staking Reward
  if(!await symbioticStakingReward.hasRole(await symbioticStakingReward.DEFAULT_ADMIN_ROLE(), admin)) {
    await symbioticStakingReward.initialize(
      admin,
      await proofMarketplace.getAddress(),
      await symbioticStaking.getAddress(),
      USDC,
    );
    console.log("SymbioticStakingReward initialized");
  }

  // Prover Manager
  if(!await proverManager.hasRole(await proverManager.DEFAULT_ADMIN_ROLE(), admin)) {
    await proverManager.initialize(
      admin,
      await proofMarketplace.getAddress(),
      await stakingManager.getAddress(),
      await entityKeyRegistry.getAddress()
    );
    console.log("ProverManager initialized");
  }

  // Proof Marketplace
  if(!await proofMarketplace.hasRole(await proofMarketplace.DEFAULT_ADMIN_ROLE(), admin)) {
    await proofMarketplace.initialize(
      admin,
      USDC,
      treasury, // TODO: set treasury address
      await proverManager.getAddress(),
      await entityKeyRegistry.getAddress(),
      config.marketCreationCost
    );
    console.log("ProofMarketplace initialized");
  }

  // Entity Key Registry
  if(!await entityKeyRegistry.hasRole(await entityKeyRegistry.DEFAULT_ADMIN_ROLE(), admin)) {
    await entityKeyRegistry.initialize(admin, []);
    console.log("EntityKeyRegistry initialized");
  }

  // Attestation Verifier
  if(!await attestationVerifier.hasRole(await attestationVerifier.DEFAULT_ADMIN_ROLE(), admin)) {
    await attestationVerifier.initialize([], [], admin);
    console.log("AttestationVerifier initialized");
  }

  //---------------------------------------- Initialize ----------------------------------------//

  return "Initialize Done";
}

deploy().then(console.log).then(initialize).then(console.log).catch(console.error);