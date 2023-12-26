import { ethers } from "hardhat";

// async function main(): Promise<string> {
//   const signers = await ethers.getSigners();
//   for (let index = 1; index < signers.length; index++) {
//     const element = signers[index];
//     const tx = await signers[0].sendTransaction({ to: element.address, value: "10000000000000000" });
//     const receipt = await tx.wait();
//     console.log("receipt", receipt?.hash);
//   }
//   return "Done";
// }

async function main(): Promise<string> {
  let address = "0xd7E109d2219b5b5b90656FB8B33F2ba679b22062";
  const signers = await ethers.getSigners();

  const tx = await signers[0].sendTransaction({ to: address, value: "150000000000000000" });
  const receipt = await tx.wait();
  console.log("receipt", receipt?.hash);
  return "Done";
}

main().then(console.log).catch(console.log);
