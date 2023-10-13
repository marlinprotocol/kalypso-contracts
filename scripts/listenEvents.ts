import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists } from "../helpers";
import { GeneratorRegistry__factory, ProofMarketPlace__factory } from "../typechain-types";

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

  const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, admin);
  proof_market_place.on(proof_market_place.filters.AskCreated, (askId) => {
    console.log({ event: "ask created", askId });

    proof_market_place.listOfAsk(askId).then(console.log).catch(console.log);
  });

  proof_market_place.on(proof_market_place.filters.TaskCreated, (askId, taskId) => {
    console.log({ event: "task created", askId, taskId });
  });

  const generator_registry = GeneratorRegistry__factory.connect(addresses.proxy.generator_registry, admin);

  generator_registry.on(generator_registry.filters.RegisteredGenerator, (generator, marketId) => {
    console.log({ event: "generator registered", generator, marketId });
  });

  generator_registry.on(generator_registry.filters.DeregisteredGenerator, (generator, marketId) => {
    console.log({ event: "degenerator registered", generator, marketId });
  });
  return "Done";
}

main().then(console.log).catch(console.log);
