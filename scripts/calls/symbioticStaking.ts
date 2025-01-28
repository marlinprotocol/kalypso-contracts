// "Measurements": {
//   "HashAlgorithm": "Sha384 { ... }",
//   "PCR0": "d5a9d4615261fd6d354df3d5a82637e9dd0ac94d2cebd22c0f15ecef216cf4032e9045a8d27e3eb558350c7acf061835",
//   "PCR1": "bcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63f",
//   "PCR2": "ce0562651ffea8670e80328bfc85f5346a6960f270cbda3920933ffbaa561f302536a288ac3dc66773115ccf3176422a"
// }

import { SymbioticStaking__factory } from '../../typechain-types';
import { getConfig } from '../helper';

const pcr0 = "0x3010987bf1dc43bdf6204ff7c62f4c837fafec8212f92a404edf83675eb0a28867dbb5ae894446c484dbd0e13b2b7ab7";
const pcr1 = "0xbcdf05fefccaa8e55bf2c8d6dee9e79bbff31e34bf28a99aa19e6b29c37ee80b214a414b7607236edf26fcb78654e63f";
const pcr2 = "0xa336db682562a9e77a7eaa8525bd9546af953a91fa0a5eddcad0a2772d8e19147873a851585cfda54cd6a8357db0812e";

async function main() {

  const { chainId, signers, addresses } = await getConfig();

  const admin = signers[0];

  const symbioticStaking = SymbioticStaking__factory.connect("0xE7136641cB2c94d318779c3B6BEb997dC5B2E574", signers[0]);

  let tx;
  // // Grant BRIDGE_ENCLAVE_UPDATES_ROLE to admin
  // let tx = await symbioticStaking.grantRole(await symbioticStaking.BRIDGE_ENCLAVE_UPDATES_ROLE(), await admin.getAddress()); 
  // await tx.wait();

  // Add PCR0, PCR1, PCR2 to enclave
  tx = await symbioticStaking.addEnclaveImage(
    pcr0,  // PCR0
    pcr1,  // PCR1
    pcr2   // PCR2
  );  
  await tx.wait();

  return "Done";
}

main().then(console.log).catch(console.error);