import BigNumber from 'bignumber.js';

import {
  EntityKeyRegistry__factory,
  IStakingPool,
  NativeStaking__factory,
  ProofMarketplace__factory,
  StakingManager__factory,
  SymbioticStaking__factory,
  SymbioticStakingReward__factory,
} from '../../typechain-types';
import { getConfig } from '../helper';

async function main() {
  const { chainId, signers, addresses } = await getConfig();

  const admin = signers[0];

  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, admin);
  const proofMarketplace = ProofMarketplace__factory.connect(addresses.proxy.proofMarketplace, admin);
  const nativeStaking = NativeStaking__factory.connect(addresses.proxy.nativeStaking, admin);
  const stakingManager = StakingManager__factory.connect(addresses.proxy.stakingManager, admin);
  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbioticStaking, admin);
  const symbioticStakingReward = SymbioticStakingReward__factory.connect(addresses.proxy.symbioticStakingReward, admin);

  // TODO: set this address
  const WETH = addresses.mockToken.weth;
  const POND = addresses.mockToken.pond;

  /*-------------------------------- StakingManager Setup --------------------------------*/

  const ONE_ETH = new BigNumber(10).pow(18);
  const TWENTY_PERCENT = ONE_ETH.multipliedBy(20).dividedBy(100); 
  const SIXTY_PERCENT = ONE_ETH.multipliedBy(60).dividedBy(100);
  const FOURTY_PERCENT = ONE_ETH.multipliedBy(40).dividedBy(100);
  const TEN_MINUTES = 10 * 60; // 10 minutes

  // Add Staking Pools
  await stakingManager.addStakingPool(await nativeStaking.getAddress(), 0);
  console.log("NativeStaking added to StakingManager");

  await stakingManager.addStakingPool(await symbioticStaking.getAddress(), ONE_ETH.toString());
  console.log("SymbioticStaking added to StakingManager");
  console.log("Reward shares set for NativeStaking(0%) and SymbioticStaking(100%");

  // Set EnabledPool
  await stakingManager.setPoolEnabled(await nativeStaking.getAddress(), true);
  console.log("NativeStaking enabled");
  await stakingManager.setPoolEnabled(await symbioticStaking.getAddress(), true);
  console.log("SymbioticStaking enabled");

  /*-------------------------------- NativeStaking Setup --------------------------------*/
  
  // TODO: weight will be twisted each time new token is added, need to fix the contract logic
  await nativeStaking.addStakeToken(POND, ONE_ETH.toString());
  console.log("POND added to NativeStaking");
  await nativeStaking.setStakeAmountToLock(POND, );
  console.log("Stake amount to lock set for POND");

  // /*-------------------------------- SymbioticStaking Config --------------------------------*/

  // TODO: weight will be twisted each time new token is added, need to fix the contract logic
  // Add Stake Tokens
  await symbioticStaking.addStakeToken(POND, SIXTY_PERCENT.toString()); // POND: 60%
  console.log("POND added to SymbioticStaking");
  await symbioticStaking.addStakeToken(WETH, FOURTY_PERCENT.toString()); // WETH: 40%
  console.log("WETH added to SymbioticStaking");
  await symbioticStaking.addStakeToken("0x5e478cb7576906fe2a443684adcd9a0dfc547abd", TWENTY_PERCENT.toString()); // Arbitrary: 20%
  console.log("Arbitrary added to SymbioticStaking");

  // Set Amount to Lock
  await symbioticStaking.setAmountToLock(POND, ONE_ETH.multipliedBy(2).toString()); // Lock 2 POND per job
  console.log("Amount to lock set for POND");
  await symbioticStaking.setAmountToLock(WETH, ONE_ETH.multipliedBy(2).toString()); // Lock 2 WETH per job
  console.log("Amount to lock set for WETH");
  await symbioticStaking.setAmountToLock("0x5e478cb7576906fe2a443684adcd9a0dfc547abd", ONE_ETH.multipliedBy(10).toString()); // Lock 10 WETH per job
  console.log("Amount to lock set for 0x5e478cb7576906fe2a443684adcd9a0dfc547abd");

  // Set Base Transmitter Comission Rate
  await symbioticStaking.setBaseTransmitterComissionRate(TWENTY_PERCENT.toString()); // Base Transmitter Comission: 20%
  console.log("Base Transmitter Comission set");

  // Set Submission Cooldown
  await symbioticStaking.setSubmissionCooldown(TEN_MINUTES);
  console.log("Submission Cooldown set");
  
  return "Done";
}

main().then(console.log).catch(console.error);
