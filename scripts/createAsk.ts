import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
  let admin = signers[0];
  let tokenHolder = signers[1];
  let treasury = signers[2];
  let marketCreator = signers[3];
  let generator = signers[4];
  let matchingEngine = signers[5];
  let prover = signers[6];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    throw new Error("token contract not deployed");
  }

  if (!addresses.proxy.proofMarketPlace) {
    throw new Error("proofMarketPlace contract not deployed");
  }

  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, prover);
  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, prover);

  if (!addresses.marketId) {
    throw new Error("Market not created");
  }

  for (let index = 0; index < 20; index++) {
    const assignmentExpiry = 10000000;
    const latestBlock = await admin.provider.getBlockNumber();
    const timeTakenForProofGeneration = 10000000;
    const maxTimeForProofGeneration = 10000000;

    const reward = "100000000000000000";
    const txReceipt = await (await mockToken.approve(await proofMarketPlace.getAddress(), reward)).wait();
    console.log("approve number", index, txReceipt?.hash);

    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(
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

    const tx = await proofMarketPlace.createAsk({
      marketId: addresses.marketId,
      proverData: inputBytes,
      reward,
      expiry: latestBlock + assignmentExpiry,
      timeTakenForProofGeneration,
      deadline: latestBlock + maxTimeForProofGeneration,
      proverRefundAddress: await prover.getAddress(),
    });

    const receipt = await tx.wait();
    console.log("ask number", index, receipt?.hash);
  }

  return `Done`;
}

main().then(console.log).catch(console.log);
