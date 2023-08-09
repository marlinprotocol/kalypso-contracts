import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { ProofMarketPlace__factory } from "../typechain-types";

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
  // let treasury = signers[2];
  // let marketCreator = signers[3];
  // let generator = signers[4];
  // let matchingEngine = signers[5];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, admin);

  //   Log { address: 0x56d030fe5d75211db0ca84fcc1ee19615fa19105, topics: [0x554eecb442b1ba28cd7de5776942c613219c455bc5cb87f92e137bc9d42649c7, 0x0000000000000000000000000000000000000000000000000000000000000029, 0x0000000000000000000000000000000000000000000000000000000000000000], data: Bytes(0x), block_hash: Some(0xba14ec9a7bb34b89e2a77e4f736bbdbfe34400784a010bba6f172ef74d10439d), block_number: Some(4047387), transaction_hash: Some(0xea6f874914f16b0ae90226a357fd760fa2e3b0b59dafad36c319da67e8514e58), transaction_index: Some(42), log_index: Some(149), transaction_log_index: None, log_type: None, removed: Some(false) }
  const filter = proofMarketPlace.on(proofMarketPlace.filters.TaskCreated(), (askId, taskId) => {
    console.log({ taskId: taskId.toString(), askId: askId.toString() });

    proofMarketPlace.listOfAsk(askId).then(console.log);
  });
  await filter;
  return "Done";
}

main().then(console.log).catch(console.log);
