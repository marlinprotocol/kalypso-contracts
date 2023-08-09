import { ethers } from "hardhat";
import { randomBytes } from "crypto";
import { bytesToHexString, checkFileExists, generateRandomBytes, generatorDataToBytes } from "../helpers";
import { GeneratorRegistry__factory, MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";
import BigNumber from "bignumber.js";

import * as fs from "fs";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";

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
  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  const admin = signers[0];
  const tokenHolder = signers[1];
  // let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  let matchingEngine = signers[5];
  let prover = signers[6];

  const eventsToEmit = 100;
  for (let index = 0; index < eventsToEmit; index++) {
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    console.log("SAVE BUT DO NOT SHARE THIS:", privateKey);

    var wallet = new ethers.Wallet(privateKey, admin.provider);
    console.log("Address: " + wallet.address);

    let tx = await admin.sendTransaction({ to: wallet.address, value: "1489249850000000" });
    console.log("send dust ether to newly created wallet", (await tx.wait())?.hash);

    const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
    tx = await mockToken.connect(tokenHolder).transfer(wallet.address, config.generatorStakingAmount);
    console.log("send mock tokens to newly created wallet", (await tx.wait())?.hash);

    console.log("start registering", index);
    tx = await mockToken.connect(wallet).approve(addresses.proxy.generatorRegistry, config.generatorStakingAmount);
    console.log("complete approval", (await tx.wait())?.hash);

    const today = new Date();
    const generatorData = {
      name: `Generator Index ${today.toDateString()} - ${index}`,
      time: 10000,
      generatorOysterPubKey: "0x" + bytesToHexString(await generateRandomBytes(64)),
      computeAllocation: 100,
    };

    const geneatorDataString = generatorDataToBytes(generatorData);
    const generatorRegistry = GeneratorRegistry__factory.connect(addresses.proxy.generatorRegistry, admin);
    tx = await generatorRegistry.connect(wallet).register(
      {
        rewardAddress: await wallet.getAddress(),
        generatorData: geneatorDataString,
        amountLocked: 0,
        minReward: new BigNumber(10).pow(6).toFixed(0),
      },
      addresses.marketId,
    );
    // console.log({estimate: estimate.toString(), bal: await ethers.provider.getBalance(wallet.address)})
    console.log("generator registration transaction", (await tx.wait())?.hash);

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
    const reward = "100000000000000000";
    tx = await mockToken.transfer(prover.address, reward);
    console.log("Send mock tokens to prover", (await tx.wait())?.hash);

    tx = await mockToken.connect(prover).approve(addresses.proxy.proofMarketPlace, reward);
    console.log("prover allowance to proof marketplace", (await tx.wait())?.hash);

    const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, prover);

    const assignmentExpiry = 10000000;
    const latestBlock = await admin.provider.getBlockNumber();
    const timeTakenForProofGeneration = 10000000;
    const maxTimeForProofGeneration = 10000000;

    const askId = await proofMarketPlace.askCounter();
    tx = await proofMarketPlace.connect(prover).createAsk({
      marketId: addresses.marketId,
      proverData: inputBytes,
      reward,
      expiry: latestBlock + assignmentExpiry,
      timeTakenForProofGeneration,
      deadline: latestBlock + maxTimeForProofGeneration,
      proverRefundAddress: await prover.getAddress(),
    });
    console.log("create new ask", (await tx.wait())?.hash);

    tx = await proofMarketPlace.connect(matchingEngine).assignTask(askId.toString(), wallet.address);
    console.log("Created Task", (await tx.wait())?.hash, "index", index);
  }
  return "Emit Tasks";
}

main().then(console.log).catch(console.log);
