import { BytesLike } from 'ethers';

import { SymbioticStaking__factory } from '../typechain-types';
import { config } from './helper';

async function main() {

  const { chainId, signers, addresses } = await config();

  const symbioticStaking = SymbioticStaking__factory.connect(addresses.proxy.symbiotic_staking, signers[0]);

  const tx = await symbioticStaking.setSubmissionCooldown(60*10);
  await tx.wait();

  return "Done";
}

main().then(console.log).catch(console.error);