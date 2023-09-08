import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";

import { a as plonkInputs } from "../helpers/sample/plonk/verification_params.json";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  let admin = signers[0];
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

  if (!addresses.plonkMarketId) {
    throw new Error("plonkMarketId not created");
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

    let inputBytes = abiCoder.encode(["bytes32[]"], [[plonkInputs]]);

    const tx = await proofMarketPlace.createAsk(
      {
        marketId: addresses.plonkMarketId,
        proverData: inputBytes,
        reward,
        expiry: latestBlock + assignmentExpiry,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      },
      false,
      0,
      "0x",
      "0x",
    );

    const receipt = await tx.wait();
    console.log("ask number", index, receipt?.hash);
  }

  return `Done`;
}

main().then(console.log).catch(console.log);