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

  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, admin);
  proofMarketPlace.on(proofMarketPlace.filters.AskCreated, (askId) => {
    console.log({ event: "ask created", askId });

    proofMarketPlace.listOfAsk(askId).then(console.log).catch(console.log);
  });

  proofMarketPlace.on(proofMarketPlace.filters.TaskCreated, (askId, taskId) => {
    console.log({ event: "task created", askId, taskId });
  });

  const generatorRegistry = GeneratorRegistry__factory.connect(addresses.proxy.generatorRegistry, admin);

  generatorRegistry.on(generatorRegistry.filters.RegisteredGenerator, (generator, marketId) => {
    console.log({ event: "generator registered", generator, marketId });
  });

  generatorRegistry.on(generatorRegistry.filters.DeregisteredGenerator, (generator, marketId) => {
    console.log({ event: "degenerator registered", generator, marketId });
  });
  return "Done";
}

main().then(console.log).catch(console.log);