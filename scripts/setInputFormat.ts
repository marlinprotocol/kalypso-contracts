import { ethers } from "hardhat";
import * as fs from "fs";

import { InputAndProofFormatRegistry__factory } from "../typechain-types";
import { createFileIfNotExists } from "../helpers";

async function main(): Promise<any> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  let admin = signers[0];

  const path = `./addresses/${chainId}.json`;
  createFileIfNotExists(path);

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (addresses?.proxy?.inputAndProofFormat) {
    const inputAndProofFormat = InputAndProofFormatRegistry__factory.connect(
      addresses.proxy.inputAndProofFormat,
      admin,
    );
    const zkbMarketId = addresses.zkbMarketId;
    let tx = await inputAndProofFormat.connect(admin).setInputFormat(zkbMarketId, ["uint256[5]"]);
    await tx.wait();

    tx = await inputAndProofFormat.connect(admin).setProofFormat(zkbMarketId, ["uint256[8]"]);
    await tx.wait();

    const inputsArrayLength = await inputAndProofFormat.inputArrayLength(zkbMarketId);
    const proofArrayLength = await inputAndProofFormat.proofArrayLength(zkbMarketId);

    const inputFormat: string[] = []; //type of input is stored as string here
    const proofFormat: string[] = []; // type of proof is stored as string here

    for (let index = 0; index < inputsArrayLength; index++) {
      inputFormat.push(await inputAndProofFormat.inputs(zkbMarketId, index));
    }

    for (let index = 0; index < proofArrayLength; index++) {
      proofFormat.push(await inputAndProofFormat.proofs(zkbMarketId, index));
    }

    return { inputFormat, proofFormat };
  }

  throw new Error("Market Id, or contract missing");
}

main().then(console.log).catch(console.log);
