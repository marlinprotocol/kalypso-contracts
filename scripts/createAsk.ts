import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists, secret_operations } from "../helpers";
import { MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";

import * as input from "../data/transferVerifier/1/public.json";
import * as secret from "../data/transferVerifier/1/secret.json";
import BigNumber from "bignumber.js";

const matching_engine_publicKey = fs.readFileSync("./data/matching_engine/public_key_2048.pem", "utf-8");

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
  const reward = "1200431";
  const runs = 20;

  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, prover);
  const platformToken = MockToken__factory.connect(addresses.proxy.platformToken);

  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, prover);

  let abiCoder = new ethers.AbiCoder();
  let inputBytes = abiCoder.encode(
    ["uint256[5]"],
    [[input.root, input.nullifier, input.out_commit, input.delta, input.memo]],
  );
  const platformFee = new BigNumber((await proofMarketPlace.costPerInputBytes()).toString()).multipliedBy(
    (inputBytes.length - 2) / 2,
  );

  let tx = await platformToken
    .connect(tokenHolder)
    .transfer(await prover.getAddress(), platformFee.multipliedBy(runs).toFixed());
  console.log("send platform tokens to prover", (await tx.wait())?.hash);

  tx = await platformToken
    .connect(prover)
    .approve(await proofMarketPlace.getAddress(), platformFee.multipliedBy(runs).toFixed());
  console.log("prover allowance of platform token to proof marketplace", (await tx.wait())?.hash);

  tx = await mockToken
    .connect(tokenHolder)
    .transfer(prover.address, new BigNumber(reward).multipliedBy(runs).toFixed());
  console.log("Send mock tokens to prover", (await tx.wait())?.hash);

  tx = await mockToken
    .connect(prover)
    .approve(addresses.proxy.proofMarketPlace, new BigNumber(reward).multipliedBy(runs).toFixed());
  console.log("prover allowance to proof marketplace", (await tx.wait())?.hash);

  if (!addresses.marketId) {
    throw new Error("marketId not created");
  }

  for (let index = 0; index < runs; index++) {
    const assignmentExpiry = 10000000;
    const latestBlock = await admin.provider.getBlockNumber();
    const timeTakenForProofGeneration = 10000000;
    const maxTimeForProofGeneration = 10000000;

    const secretString = JSON.stringify(secret);
    const result = await secret_operations.encryptDataWithRSAandAES(secretString, matching_engine_publicKey);
    const aclHex = "0x" + secret_operations.base64ToHex(result.aclData);
    const encryptedSecretInputs = "0x" + result.encryptedData;

    const askId = await proofMarketPlace.askCounter();
    const tx = await proofMarketPlace.connect(prover).createAsk(
      {
        marketId: addresses.marketId,
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
    console.log("ask number", index, transactionhash);
  }

  return `Done`;
}

main().then(console.log).catch(console.log);
