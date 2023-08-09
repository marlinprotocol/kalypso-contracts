import { ethers } from "hardhat";

async function main(): Promise<string> {
  const signers = await ethers.getSigners();
  for (let index = 1; index < signers.length; index++) {
    const element = signers[index];
    const tx = await signers[0].sendTransaction({ to: element.address, value: "100000000000000000" });
    const receipt = await tx.wait();
    console.log("receipt", receipt?.hash);
  }
  return "Done";
}

main().then(console.log).catch(console.log);
