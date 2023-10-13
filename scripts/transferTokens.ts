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

  const transferTo = "0x4d85CEA118DcEaA3F187e97aDd84F265bF31b420";
  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.payment_token) {
    throw new Error("token contract not deployed");
  }

  if (!addresses.proxy.staking_token) {
    throw new Error("token contract not deployed");
  }

  const ethBalance = await admin.provider.getBalance(transferTo);
  if (new BigNumber(ethBalance.toString()).lt("31750928600000000")) {
    (await treasury.sendTransaction({ to: transferTo, value: "31750928600000000" })).wait();
  }

  const payment_token = MockToken__factory.connect(addresses.proxy.payment_token, tokenHolder);
  let tx = await payment_token.connect(tokenHolder).transfer(transferTo, "1000000000000000000000");
  let receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  const staking_token = MockToken__factory.connect(addresses.proxy.staking_token, tokenHolder);
  tx = await staking_token.connect(tokenHolder).transfer(transferTo, "1000000000000000000000");
  receipt = await tx.wait();
  console.log(`Done: ${receipt?.hash}`);

  return "Done";
}

main().then(console.log).catch(console.log);
