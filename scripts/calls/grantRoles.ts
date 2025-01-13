import { EntityKeyRegistry__factory, NativeStaking__factory, ProofMarketplace__factory, StakingManager__factory, SymbioticStaking__factory, SymbioticStakingReward__factory } from '../../typechain-types';
import { getConfig } from '../helper';

async function main() {

  
  const { chainId, signers, addresses } = await getConfig();

  let tx;
  
  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, signers[0]);
  const proofMarketplace = ProofMarketplace__factory.connect(addresses.proxy.proofMarketplace, signers[0]);
  const nativeStaking = NativeStaking__factory.connect(addresses.proxy.nativeStaking, signers[0]);
  const stakingManager = StakingManager__factory.connect(addresses.proxy.stakingManager, signers[0]);
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbioticStaking, signers[0]);
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(addresses.proxy.symbioticStakingReward, signers[0]);

  /* EntityKeyRegistry */

  // // ENTITY_KEY_REGISTRY.KEY_REGISTER_ROLE() -> GENERATOR_REGISTRY(0x4743a2c7a96c9fbed8b7ead980ad01822f9711db)
  // // grant EntityKeyRegistry.KEY_REGISTER_ROLE to ProverManager
  tx = await entityKeyRegistry.grantRole(await entityKeyRegistry.KEY_REGISTER_ROLE(), addresses.proxy.proverManager);
  await tx.wait();
  console.log("EntityKeyRegistry.KEY_REGISTER_ROLE granted to ProverManager");

  // // ENTITY_KEY_REGISTRY.MODERATOR_ROLE() -> CUSTOM_ADDRESS(0x47d40316867853189e1e04dc1eb53dc71c8eb946)
  // // grant EntityKeyRegistry.MODERATOR_ROLE to 0x47d40316867853189e1e04dc1eb53dc71c8eb946
  // tx = await entityKeyRegistry.grantRole(await entityKeyRegistry.MODERATOR_ROLE(), "0x47d40316867853189e1e04dc1eb53dc71c8eb946");
  // await tx.wait();
  // console.log("EntityKeyRegistry.MODERATOR_ROLE granted to 0x47d40316867853189e1e04dc1eb53dc71c8eb946");
  // /* ProofMarketplace */

  // // PROOF_MARKETPLACE.UPDATER_ROLE() -> CUSTOM_ADDRESS(0x47d40316867853189e1e04dc1eb53dc71c8eb946)
  // // grant ProofMarketplace.UPDATER_ROLE to 0x47d40316867853189e1e04dc1eb53dc71c8eb946
  // tx = await proofMarketplace.grantRole(await proofMarketplace.UPDATER_ROLE(), "0x47d40316867853189e1e04dc1eb53dc71c8eb946");
  // await tx.wait();
  // console.log("ProofMarketplace.UPDATER_ROLE granted to 0x47d40316867853189e1e04dc1eb53dc71c8eb946");
  // // PROOF_MARKETPLACE.SYMBIOTIC_STAKING_ROLE() -> SYMBIOTIC_STAKING(0x078b3f1504a4b5bc08eb057cd2fc8dd790459163)
  // // grant ProofMarketplace.SYMBIOTIC_STAKING_ROLE to SYMBIOTIC_STAKING
  // tx = await proofMarketplace.grantRole(await proofMarketplace.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  // await tx.wait();
  // console.log("ProofMarketplace.SYMBIOTIC_STAKING_ROLE granted to SYMBIOTIC_STAKING");

  // /* NativeStaking */

  // // NATIVE_STAKING.STAKING_MANAGER_ROLE() -> STAKING_MANAGER(0xaf2ae7ce949665eba8a43a31df73f4814252cc84)
  // // grant NativeStaking.STAKING_MANAGER_ROLE to STAKING_MANAGER
  // tx = await nativeStaking.grantRole(await nativeStaking.STAKING_MANAGER_ROLE(), addresses.proxy.stakingManager);
  // await tx.wait();
  // console.log("NativeStaking.STAKING_MANAGER_ROLE granted to STAKING_MANAGER");
  
  // /* StakingManager */

  // // "STAKING_MANAGER.PROVER_REGISTRY_ROLE() -> GENERATOR_REGISTRY"(0x4743a2c7a96c9fbed8b7ead980ad01822f9711db)
  // // grant StakingManager.PROVER_MANAGER_ROLE to PROVER_MANAGER
  // tx = await stakingManager.grantRole(await stakingManager.PROVER_MANAGER_ROLE(), addresses.proxy.proverManager);
  // await tx.wait();
  // console.log("StakingManager.PROVER_MANAGER_ROLE granted to PROVER_MANAGER");

  // // "STAKING_MANAGER.SYMBIOTIC_STAKING_ROLE() -> SYMBIOTIC_STAKING"(0x078b3f1504a4b5bc08eb057cd2fc8dd790459163)
  // // grant StakingManager.SYMBIOTIC_STAKING_ROLE to SYMBIOTIC_STAKING
  // tx = await stakingManager.grantRole(await stakingManager.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  // await tx.wait();
  // console.log("StakingManager.SYMBIOTIC_STAKING_ROLE granted to SYMBIOTIC_STAKING");
  // /* SymbioticStaking */

  // // SYMBIOTIC_STAKING.STAKING_MANAGER_ROLE() -> STAKING_MANAGER(0xaf2ae7ce949665eba8a43a31df73f4814252cc84)
  // // grant SymbioticStaking.STAKING_MANAGER_ROLE to STAKING_MANAGER
  // tx = await symbioticStaking.grantRole(await symbioticStaking.STAKING_MANAGER_ROLE(), addresses.proxy.stakingManager);
  // await tx.wait();
  // console.log("SymbioticStaking.STAKING_MANAGER_ROLE granted to STAKING_MANAGER");
  // /* SymbioticStakingReward */

  // // SYMBIOTIC_STAKING_REWARD.SYMBIOTIC_STAKING_ROLE() -> SYMBIOTIC_STAKING(0x078b3f1504a4b5bc08eb057cd2fc8dd790459163)
  // // grant SymbioticStakingReward.SYMBIOTIC_STAKING_ROLE to SYMBIOTIC_STAKING
  // tx = await symbioticStakingReward.grantRole(await symbioticStakingReward.SYMBIOTIC_STAKING_ROLE(), addresses.proxy.symbioticStaking);
  // await tx.wait();
  // console.log("SymbioticStakingReward.SYMBIOTIC_STAKING_ROLE granted to SYMBIOTIC_STAKING");


  // `"CUSTOM_ADDRESS"(0xc6de583b87716e351e4fb60d687b9330877dbaf4) does not have role UPDATER_ROLE in PROOF_MARKETPLACE`
  // grant PROOF_MARKETPLACE.UPDATER_ROLE to 0xc6de583b87716e351e4fb60d687b9330877dbaf4
  tx = await proofMarketplace.grantRole(await proofMarketplace.UPDATER_ROLE(), "0xc6de583b87716e351e4fb60d687b9330877dbaf4");
  await tx.wait();
  console.log("PROOF_MARKETPLACE.UPDATER_ROLE granted to 0xc6de583b87716e351e4fb60d687b9330877dbaf4");
  
  return "Done";
}

main().then(console.log).catch(console.error);