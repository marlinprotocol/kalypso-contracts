import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { MockToken__factory } from "../typechain-types";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  let admin = signers[0];
  let tokenHolder = signers[1];
  // let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  // let matchingEngine = signers[5];

  const transferTo = "0xCc9F0defA87Ecba1dFb6D7C9103F01fEAF547dba";
  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    throw new Error("token contract not deployed");
  }

  (await admin.sendTransaction({ to: transferTo, value: "10000000000000000" })).wait();

  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
  let tx = await mockToken.connect(tokenHolder).transfer(transferTo, "123000000000000000000");
  let receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  const platformToken = MockToken__factory.connect(addresses.proxy.platformToken, tokenHolder);
  tx = await platformToken.connect(tokenHolder).transfer(transferTo, "154000000000000000000");
  receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  return "Done";
}

main().then(console.log).catch(console.log);
