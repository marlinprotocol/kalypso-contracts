import { ethers } from "hardhat";

// async function main(): Promise<string> {
//   const signers = await ethers.getSigners();
//   for (let index = 1; index < signers.length; index++) {
//     const element = signers[index];
//     const tx = await signers[0].sendTransaction({ to: element.address, value: "100000000000000000" });
//     const receipt = await tx.wait();
//     console.log("receipt", receipt?.hash);
//   }
//   return "Done";
// }

async function main(): Promise<string> {
  let address = "0xCc9F0defA87Ecba1dFb6D7C9103F01fEAF547dba";
  const signers = await ethers.getSigners();

  const tx = await signers[0].sendTransaction({ to: address, value: "1500000000000000000" });
  const receipt = await tx.wait();
  console.log("receipt", receipt?.hash);
  return "Done";
}

main().then(console.log).catch(console.log);
