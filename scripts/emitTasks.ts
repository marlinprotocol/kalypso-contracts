import { ethers } from "hardhat";
import { gzip, ungzip } from "node-gzip";
import { randomBytes } from "crypto";
import {
  bytesToHexString,
  checkFileExists,
  generateRandomBytes,
  generatorDataToBytes,
  jsonToBytes,
  secret_operations,
  splitHexString,
  utf8ToHex,
} from "../helpers";
import {
  GeneratorRegistry__factory,
  MockToken__factory,
  ProofMarketPlace__factory,
  EntityKeyRegistry__factory,
} from "../typechain-types";

import BigNumber from "bignumber.js";

import * as fs from "fs";

import * as input from "../data/transferVerifier/1/public.json";
import * as secret from "../data/transferVerifier/1/secret.json";
import { BytesLike } from "ethers";

const matching_engine_publicKey = fs.readFileSync("./data/matching_engine/public_key_2048.pem", "utf-8");
const matching_engine_privatekey = fs.readFileSync("./data/matching_engine/private_key_2048.pem", "utf-8");

const generator_publickey = fs.readFileSync("./data/demo_generator/public_key.pem", "utf-8");
const generator_privatekey = fs.readFileSync("./data/demo_generator/private_key.pem", "utf-8");

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

  const eventsToEmit = 1;
  for (let index = 0; index < eventsToEmit; index++) {
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    console.log("SAVE BUT DO NOT SHARE THIS:", privateKey);

    var wallet = new ethers.Wallet(privateKey, admin.provider);
    console.log("Address: " + wallet.address);

    let tx = await admin.sendTransaction({ to: wallet.address, value: "5000000000000000" });
    console.log("send dust ether to newly created wallet", (await tx.wait())?.hash);

    const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
    tx = await mockToken.connect(tokenHolder).transfer(wallet.address, config.generatorStakingAmount);
    console.log("send mock tokens to newly created wallet", (await tx.wait())?.hash);

    console.log("start registering", index);
    tx = await mockToken.connect(wallet).approve(addresses.proxy.generator_registry, config.generatorStakingAmount);
    console.log("complete approval", (await tx.wait())?.hash);

    const today = new Date();
    const generatorData = {
      name: `Generator Index ${today.toDateString()} - ${index}`,
      time: 10000,
      generatorOysterPubKey: "0x" + bytesToHexString(await generateRandomBytes(64)),
      computeAllocation: 100,
    };

    const geneatorDataString = generatorDataToBytes(generatorData);
    const generator_registry = GeneratorRegistry__factory.connect(addresses.proxy.generator_registry, admin);
    tx = await generator_registry.connect(wallet).register(await wallet.getAddress(), 100, geneatorDataString);
    await tx.wait();
    tx = await generator_registry.connect(wallet).stake(await wallet.getAddress(), config.generatorStakingAmount);
    await tx.wait();
    tx = await generator_registry.connect(wallet).joinMarketPlace(
      addresses.zkbMarketId,
      new BigNumber(10)
        .pow(19)
        .multipliedBy(index + 1)
        .toFixed(),
      1000,
      index + 1,
    );

    // console.log({estimate: estimate.toString(), bal: await ethers.provider.getBalance(wallet.address)})
    console.log("generator registration transaction", (await tx.wait())?.hash);

    const entity_registry = EntityKeyRegistry__factory.connect(addresses.proxy.entity_registry, wallet);
    const pubBytes = utf8ToHex(generator_publickey);
    tx = await entity_registry.updatePubkey("0x" + pubBytes, "0x");
    console.log("generator broadcast pubkey transaction", (await tx.wait())?.hash);

    let abiCoder = new ethers.AbiCoder();

    let inputBytes = abiCoder.encode(
      ["uint256[5]"],
      [[input.root, input.nullifier, input.out_commit, input.delta, input.memo]],
    );

    const reward = "1000001";
    tx = await mockToken.transfer(prover.address, reward);
    console.log("Send mock tokens to prover", (await tx.wait())?.hash);

    tx = await mockToken.connect(prover).approve(addresses.proxy.proof_market_place, reward);
    console.log("prover allowance to proof marketplace", (await tx.wait())?.hash);

    const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, prover);

    const platformFee = new BigNumber((await proof_market_place.costPerInputBytes()).toString()).multipliedBy(
      (inputBytes.length - 2) / 2,
    );

    const platformToken = MockToken__factory.connect(addresses.proxy.platformToken);
    tx = await platformToken.connect(tokenHolder).transfer(await prover.getAddress(), platformFee.toFixed());
    console.log("prover allowance of platform token to proof marketplace", (await tx.wait())?.hash);

    tx = await platformToken.connect(prover).approve(await proof_market_place.getAddress(), platformFee.toFixed());
    console.log("prover allowance of platform token to proof marketplace", (await tx.wait())?.hash);

    const assignmentExpiry = 10000000;
    const latestBlock = await admin.provider.getBlockNumber();
    const timeTakenForProofGeneration = 10000000;
    const maxTimeForProofGeneration = 10000000;

    const secretString = JSON.stringify(secret);
    const result = await secret_operations.encryptDataWithEciesAandAES(secretString, matching_engine_publicKey);
    const aclHex = "0x" + secret_operations.base64ToHex(result.aclData.toString("hex"));
    const encryptedSecretInputs = "0x" + result.encryptedData;
    const secretCompressed = await gzip(encryptedSecretInputs);

    const askId = await proof_market_place.askCounter();
    tx = await proof_market_place.connect(prover).createAsk(
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
      secretCompressed,
      aclHex,
    );
    const transactionhash = (await tx.wait())?.hash as string;
    console.log(`create new ask ID: ${askId}`, transactionhash);

    const transaction = await admin.provider.getTransaction(transactionhash);
    const decodedData = proof_market_place.interface.decodeFunctionData("createAsk", transaction?.data as BytesLike);
    const secretDataComp = decodedData[decodedData.length - 2].toString();
    const buffer_decoded = Buffer.from(secretDataComp.split("x")[1], "hex");
    const recovered_secret = await ungzip(buffer_decoded);
    const secretData = recovered_secret.toString();
    const aclData = decodedData[decodedData.length - 1];

    const decryptedData = await secret_operations.decryptDataWithEciesandAES(
      secretData.split("x")[1],
      aclData.split("x")[1],
      matching_engine_privatekey,
    );

    console.log("************** data seen by matching engine (start) *************");
    console.log(JSON.parse(decryptedData));
    console.log("************** data seen by matching engine (end) *************");

    const cipher = await secret_operations.decryptEcies(matching_engine_privatekey, aclData.split("x")[1]);
    const new_acl_hex = "0x" + (await secret_operations.encryptECIES(generator_publickey, cipher)).toString("hex");

    const taskId = await proof_market_place.taskCounter();
    tx = await proof_market_place
      .connect(matchingEngine)
      .assignTask(askId.toString(), taskId, wallet.address, new_acl_hex);
    const assignTxHash = (await tx.wait())?.hash;
    console.log(`Created Task taskId ${taskId}`, assignTxHash);

    const assignTransaction = await admin.provider.getTransaction(assignTxHash as string);
    const generatorDecodedData = proof_market_place.interface.decodeFunctionData(
      "assignTask",
      assignTransaction?.data as BytesLike,
    );
    const generator_acl = generatorDecodedData[generatorDecodedData.length - 1];

    const decryptedDataForGenerator = await secret_operations.decryptDataWithEciesandAES(
      secretData.split("x")[1],
      generator_acl.split("x")[1],
      generator_privatekey,
    );

    console.log("************** data seen by generator (start) *************");
    console.log(JSON.parse(decryptedDataForGenerator));
    console.log("************** data seen by generator (end) *************");
    // let proofBytes = abiCoder.encode(["bytes"], [plonkProof]);
    // tx = await proof_market_place.connect(admin).submitProof(taskId, proofBytes);
    // console.log("Proof Submitted", (await tx.wait())?.hash, "index", index);
  }
  return "Emit Tasks";
}

main().then(console.log).catch(console.log);
