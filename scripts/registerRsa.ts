import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists, hexToUtf8, utf8ToHex } from "../helpers";
import {} from "../typechain-types";
import { EntityKeyRegistry__factory } from "../typechain-types/factories/contracts";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("transacting on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  let matchingEngine = signers[5];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses.proxy.EntityRegistry) {
    throw new Error("EntityRegistry contract not deployed");
  }

  const entityRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.EntityRegistry, matchingEngine);
  const matchingEngineRsaPub = fs.readFileSync("./data/matching_engine/public_key_2048.pem", "utf-8");

  const pubBytes = utf8ToHex(matchingEngineRsaPub);
  const pubkeyRecovered = hexToUtf8(pubBytes);

  const tx = await entityRegistry.updatePubkey("0x" + pubkeyRecovered, "0x");
  await tx.wait();

  const pubBytesFetched = await entityRegistry.pub_key(await matchingEngine.getAddress());
  const pubBytesFetchedAndRecovered = hexToUtf8(pubBytesFetched.split("x")[1]);
  console.log({ matchingEngineRsaPub, pubkeyRecovered, pubBytesFetchedAndRecovered });

  return "Done";
}

main().then(console.log).catch(console.log);
