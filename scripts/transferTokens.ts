import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { MockToken__factory } from "../typechain-types";
import BigNumber from "bignumber.js";

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
  let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  // let matchingEngine = signers[5];

  const transferTo = "0x01f01074dc5454B15faBf1F1006864D0b71e3f19";
  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    throw new Error("token contract not deployed");
  }

  const ethBalance = await admin.provider.getBalance(transferTo);
  if (new BigNumber(ethBalance.toString()).lt("31750928600000000")) {
    (await treasury.sendTransaction({ to: transferTo, value: "31750928600000000" })).wait();
  }

  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
  let tx = await mockToken.connect(tokenHolder).transfer(transferTo, "1000000000000000000000");
  let receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  const platformToken = MockToken__factory.connect(addresses.proxy.platformToken, tokenHolder);
  tx = await platformToken.connect(tokenHolder).transfer(transferTo, "1000000000000000000000");
  receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  return "Done";
}

main().then(console.log).catch(console.log);
