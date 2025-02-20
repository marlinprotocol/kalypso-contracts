import { ProofMarketplace__factory } from '../typechain-types';
import { getConfig } from './helper';

async function main() {

  const { chainId, signers, addresses } = await getConfig();

  const proofMarketplace = ProofMarketplace__factory.connect(addresses.proxy.proofMarketplace, signers[0]);

  const tx = await proofMarketplace.grantRole(await proofMarketplace.MATCHING_ENGINE_ROLE(), "0xc6dE583B87716E351e4Fb60D687b9330877DbaF4"); 
  await tx.wait();

  return "Done";
}

main().then(console.log).catch(console.error);