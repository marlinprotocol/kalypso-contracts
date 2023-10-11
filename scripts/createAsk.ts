import { ethers } from "hardhat";
import { checkFileExists, secret_operations } from "../helpers";
import { MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";
import BigNumber from "bignumber.js";

import * as fs from "fs";

import * as input from "../data/transferVerifier/1/public.json";
import * as secret from "../data/transferVerifier/1/secret.json";

const matching_engine_publicKey = fs.readFileSync("./data/matching_engine/public_key_2048.pem", "utf-8");

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
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

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  const admin = signers[0];
  const tokenHolder = signers[1];
  let prover = signers[6];

  console.log("using token holder", await tokenHolder.getAddress());
  console.log("using prover", await prover.getAddress());
  const eventsToEmit = 20;
  for (let index = 0; index < eventsToEmit; index++) {
    const mockToken = MockToken__factory.connect(addresses.proxy.paymentToken, tokenHolder);

    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(
      ["uint256[5]"],
      [[input.root, input.nullifier, input.out_commit, input.delta, input.memo]],
    );

    const reward = "1200431";
    let tx = await mockToken.transfer(prover.address, reward);
    console.log("Send mock tokens to prover", (await tx.wait())?.hash);

    tx = await mockToken.connect(prover).approve(addresses.proxy.proofMarketPlace, reward);
    console.log("prover allowance to proof marketplace", (await tx.wait())?.hash);

    const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, prover);

    const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes()).toString()).multipliedBy(
      (inputBytes.length - 2) / 2,
    );

    const platformToken = MockToken__factory.connect(addresses.proxy.platformToken);
    tx = await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
    console.log("send platform tokens to prover", (await tx.wait())?.hash);

    tx = await platformToken.connect(prover).approve(await proofMarketPlace.getAddress(), platformFee.toFixed());
    console.log("prover allowance of platform token to proof marketplace", (await tx.wait())?.hash);

    const assignmentExpiry = 10000000;
    const latestBlock = await admin.provider.getBlockNumber();
    const timeTakenForProofGeneration = 10000000;
    const maxTimeForProofGeneration = 10000000;

    const secretString = JSON.stringify(secret);
    const result = await secret_operations.encryptDataWithEciesAandAES(secretString, matching_engine_publicKey);
    const aclHex = "0x" + result.aclData.toString("hex");
    const encryptedSecretInputs = "0x" + result.encryptedData;

    const askId = await proofMarketPlace.askCounter();
    tx = await proofMarketPlace.connect(prover).createAsk(
      {
        marketId: addresses.zkbMarketId,
        proverData: inputBytes,
        reward,
        expiry: latestBlock + assignmentExpiry,
        timeTakenForProofGeneration,
        deadline: latestBlock + maxTimeForProofGeneration,
        refundAddress: await prover.getAddress(),
      },
      true,
      1,
      encryptedSecretInputs,
      aclHex,
    );
    const transactionhash = (await tx.wait())?.hash as string;
    console.log(`create new ask ID: ${askId}`, transactionhash);
  }
  return "Emit Tasks";
}

main().then(console.log).catch(console.log);
