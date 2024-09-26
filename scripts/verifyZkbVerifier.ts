import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

const abiCoder = new ethers.AbiCoder();

let inputBytes_transfer_verifier = abiCoder.encode(
  ["uint256[5]"],
  [
    [
      transfer_verifier_inputs[0],
      transfer_verifier_inputs[1],
      transfer_verifier_inputs[2],
      transfer_verifier_inputs[3],
      transfer_verifier_inputs[4],
    ],
  ],
);

let proofBytes_transfer_verifier = abiCoder.encode(
  ["uint256[8]"],
  [
    [
      transfer_verifier_proof.a[0],
      transfer_verifier_proof.a[1],
      transfer_verifier_proof.b[0][0],
      transfer_verifier_proof.b[0][1],
      transfer_verifier_proof.b[1][0],
      transfer_verifier_proof.b[1][1],
      transfer_verifier_proof.c[0],
      transfer_verifier_proof.c[1],
    ],
  ],
);

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const path = `./addresses/${chainId}.json`;

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  let verificationResult;

  verificationResult = await run("verify:verify", {
    address: addresses.proxy.TransferVerifier,
    constructorArguments: [],
  });
  console.log({ verificationResult });

  verificationResult = await run("verify:verify", {
    address: addresses.proxy.transfer_verifier_wrapper,
    constructorArguments: [addresses.proxy.TransferVerifier, inputBytes_transfer_verifier, proofBytes_transfer_verifier],
  });
  console.log({ verificationResult });


  return "String";
}

main().then(console.log);
