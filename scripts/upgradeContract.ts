import {
  run,
} from 'hardhat';

import {
  StakingManager__factory,
  UUPSUpgradeable__factory,
} from '../typechain-types';
import { getConfig } from './helper';

async function main() {
  const { chainId, signers, addresses } = await getConfig();

  const admin = signers[0];

  // StakingManager Proxy
  const stakingManagerProxy = UUPSUpgradeable__factory.connect(addresses.proxy.stakingManager, admin);

  // New StakingManager Implementation
  const newStakingManagerImpl = await new StakingManager__factory(admin).deploy();
  await newStakingManagerImpl.waitForDeployment();

  // Upgrade StakingManager
  let tx = await stakingManagerProxy.upgradeToAndCall(await newStakingManagerImpl.getAddress(), "0x");
  await tx.wait();

  console.log("StakingManager upgraded");
  
  let verificationResult = await run("verify:verify", {
    address: await newStakingManagerImpl.getAddress(),
  });
  console.log({ verificationResult });
  
  return "Done";
}

main().then(console.log);
