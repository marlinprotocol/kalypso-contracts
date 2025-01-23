import {
  EntityKeyRegistry__factory,
  NativeStaking__factory,
  ProofMarketplace__factory,
  ProverManager__factory,
  StakingManager__factory,
  SymbioticStaking__factory,
  SymbioticStakingReward__factory,
} from "../../typechain-types";
import { getConfig } from "../helper";

async function main() {
  const { chainId, signers, addresses } = await getConfig();

  let tx;

  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, signers[0]);
  const proofMarketplace = ProofMarketplace__factory.connect(addresses.proxy.proofMarketplace, signers[0]);
  const proverManager = ProverManager__factory.connect(addresses.proxy.proverManager, signers[0]);
  const nativeStaking = NativeStaking__factory.connect(addresses.proxy.nativeStaking, signers[0]);
  const stakingManager = StakingManager__factory.connect(addresses.proxy.stakingManager, signers[0]);
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbioticStaking, signers[0]);
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(addresses.proxy.symbioticStakingReward, signers[0]);

  // TODO: all addresses below should be set

  /* EntityKeyRegistry */
  const ENTITYKEYREGISTRY_KEY_REGISTER_ROLE_ADDR = "0x";
  const ENTITYKEYREGISTRY_MODERATOR_ROLE_ADDR = "0x";
  /* ProofMarketplace */
  const PROOFMARKETPLACE_UPDATER_ROLE_ADDR = "0x";
  const PROOFMARKETPLACE_MATCHING_ENGINE_ROLE_ADDR = "0x";
  /* SymbioticStaking */
  const SYMBIOTIC_STAKING_BRIDGE_ENCLAVE_UPDATER_ROLE_ADDR = "0x";

  //---------------------------------------- EntityKeyRegistry ----------------------------------------//

  // EntityKeyRegistry.KEY_REGISTER_ROLE to ProverManager
  tx = await entityKeyRegistry.grantRole(await entityKeyRegistry.KEY_REGISTER_ROLE(), ENTITYKEYREGISTRY_KEY_REGISTER_ROLE_ADDR);
  await tx.wait();
  console.log("EntityKeyRegistry.KEY_REGISTER_ROLE granted to ProverManager");

  // EntityKeyRegistry.MODERATOR_ROLE to ENTITYKEYREGISTRY_MODERATOR_ROLE_ADDR
  tx = await entityKeyRegistry.grantRole(await entityKeyRegistry.MODERATOR_ROLE(), ENTITYKEYREGISTRY_MODERATOR_ROLE_ADDR);
  await tx.wait();
  console.log("EntityKeyRegistry.MODERATOR_ROLE granted to ENTITYKEYREGISTRY_MODERATOR_ROLE_ADDR");

  //---------------------------------------- ProofMarketplace ----------------------------------------//

  // ProofMarketplace.UPDATER_ROLE to PROOFMARKETPLACE_UPDATER_ROLE_ADDR
  tx = await proofMarketplace.grantRole(await proofMarketplace.UPDATER_ROLE(), PROOFMARKETPLACE_UPDATER_ROLE_ADDR);
  await tx.wait();
  console.log("ProofMarketplace.UPDATER_ROLE granted to PROOFMARKETPLACE_UPDATER_ROLE_ADDR");

  // ProofMarketplace.MATCHING_ENGINE_ROLE to PROOFMARKETPLACE_MATCHING_ENGINE_ROLE_ADDR
  tx = await proofMarketplace.grantRole(await proofMarketplace.MATCHING_ENGINE_ROLE(), PROOFMARKETPLACE_MATCHING_ENGINE_ROLE_ADDR);
  await tx.wait();
  console.log("ProofMarketplace.MATCHING_ENGINE_ROLE granted to PROOFMARKETPLACE_MATCHING_ENGINE_ROLE_ADDR");

  // ProofMarketplace.STAKING_MANAGER_ROLE to StakingManager
  tx = await proofMarketplace.grantRole(await proofMarketplace.STAKING_MANAGER_ROLE(), addresses.proxy.stakingManager);
  await tx.wait();
  console.log("ProofMarketplace.STAKING_MANAGER_ROLE granted to StakingManager");

  // ProofMarketplace.SYMBIOTIC_STAKING_ROLE to SymbioticStaking
  tx = await proofMarketplace.grantRole(await proofMarketplace.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  await tx.wait();
  console.log("ProofMarketplace.SYMBIOTIC_STAKING_ROLE granted to SymbioticStaking");

  // ProofMarketplace.SYMBIOTIC_STAKING_REWARD_ROLE to SymbioticStakingReward
  tx = await proofMarketplace.grantRole(await proofMarketplace.SYMBIOTIC_STAKING_REWARD_ROLE(), addresses.proxy.symbioticStakingReward);
  await tx.wait();
  console.log("ProofMarketplace.SYMBIOTIC_STAKING_REWARD_ROLE granted to SymbioticStakingReward");

  //---------------------------------------- ProverManager ----------------------------------------//

  // ProverManager.PROOF_MARKET_PLACE_ROLE to ProofMarketplace
  tx = await proverManager.grantRole(await proverManager.PROOF_MARKET_PLACE_ROLE(), addresses.proxy.proofMarketplace);
  await tx.wait();
  console.log("ProverManager.PROOF_MARKET_PLACE_ROLE granted to ProofMarketplace");

  //---------------------------------------- NativeStaking ----------------------------------------//

  // NativeStaking.STAKING_MANAGER_ROLE to STAKING_MANAGER
  tx = await nativeStaking.grantRole(await nativeStaking.STAKING_MANAGER_ROLE(), addresses.proxy.stakingManager);
  await tx.wait();
  console.log("NativeStaking.STAKING_MANAGER_ROLE granted to STAKING_MANAGER");

  //---------------------------------------- StakingManager ----------------------------------------//

  // StakingManager.PROVER_MANAGER_ROLE to PROVER_MANAGER
  tx = await stakingManager.grantRole(await stakingManager.PROVER_MANAGER_ROLE(), addresses.proxy.proverManager);
  await tx.wait();
  console.log("StakingManager.PROVER_MANAGER_ROLE granted to PROVER_MANAGER");

  // StakingManager.SYMBIOTIC_STAKING_ROLE to SYMBIOTIC_STAKING
  tx = await stakingManager.grantRole(await stakingManager.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  await tx.wait();
  console.log("StakingManager.SYMBIOTIC_STAKING_ROLE granted to SYMBIOTIC_STAKING");

  //---------------------------------------- SymbioticStaking ----------------------------------------//

  // SymbioticStaking.STAKING_MANAGER_ROLE to STAKING_MANAGER
  tx = await symbioticStaking.grantRole(await symbioticStaking.STAKING_MANAGER_ROLE(), addresses.proxy.stakingManager);
  await tx.wait();
  console.log("SymbioticStaking.STAKING_MANAGER_ROLE granted to STAKING_MANAGER");

  // SymbioticStaking.BRIDGE_ENCLAVE_UPDATER_ROLE to SYMBIOTIC_STAKING_BRIDGE_ENCLAVE_UPDATER_ROLE_ADDR
  tx = await symbioticStaking.grantRole(
    await symbioticStaking.BRIDGE_ENCLAVE_UPDATER_ROLE(),
    SYMBIOTIC_STAKING_BRIDGE_ENCLAVE_UPDATER_ROLE_ADDR,
  );
  await tx.wait();
  console.log("SymbioticStaking.BRIDGE_ENCLAVE_UPDATER_ROLE granted to SYMBIOTIC_STAKING_BRIDGE_ENCLAVE_UPDATER_ROLE_ADDR");

  //---------------------------------------- SymbioticStakingReward ----------------------------------------//

  // SymbioticStakingReward.SYMBIOTIC_STAKING_ROLE to SYMBIOTIC_STAKING
  tx = await symbioticStakingReward.grantRole(await symbioticStakingReward.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  await tx.wait();
  console.log("SymbioticStakingReward.SYMBIOTIC_STAKING_ROLE granted to SYMBIOTIC_STAKING");

  return "Done";
}

main().then(console.log).catch(console.error);
