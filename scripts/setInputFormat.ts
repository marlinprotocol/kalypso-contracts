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

  if (addresses.marketId && addresses?.proxy?.inputAndProofFormat) {
    const inputAndProofFormat = InputAndProofFormatRegistry__factory.connect(
      addresses.proxy.inputAndProofFormat,
      admin,
    );
    const marketId = addresses.circomMarketId;
    let tx = await inputAndProofFormat.connect(admin).setInputFormat(marketId, ["uint[1]"]);
    await tx.wait();

    tx = await inputAndProofFormat.connect(admin).setProofFormat(marketId, ["uint[2]", "uint[2][2]", "uint[2]"]);
    await tx.wait();

    const inputsArrayLength = await inputAndProofFormat.inputArrayLength(marketId);
    const proofArrayLength = await inputAndProofFormat.proofArrayLength(marketId);

    const inputFormat: string[] = []; //type of input is stored as string here
    const proofFormat: string[] = []; // type of proof is stored as string here

    for (let index = 0; index < inputsArrayLength; index++) {
      inputFormat.push(await inputAndProofFormat.inputs(marketId, index));
    }

    for (let index = 0; index < proofArrayLength; index++) {
      proofFormat.push(await inputAndProofFormat.proofs(marketId, index));
    }

    return { inputFormat, proofFormat };
  }

  throw new Error("Market Id, or contract missing");
}

main().then(console.log).catch(console.log);
