import { EntityKeyRegistry__factory, ProofMarketplace__factory } from '../../typechain-types';
import { getConfig } from '../helper';

async function main() {

  const { chainId, signers, addresses } = await getConfig();

  const entityKeyRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entityKeyRegistry, signers[0]);

  const tx = await entityKeyRegistry.grantRole(await entityKeyRegistry.KEY_REGISTER_ROLE(), addresses.proxy.proofMarketplace); 
  await tx.wait();

  return "Done";
}

main().then(console.log).catch(console.error);