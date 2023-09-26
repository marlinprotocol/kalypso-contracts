import { ethers } from "hardhat";
import * as fs from "fs";
import { bytesToHexString, checkFileExists, generateRandomBytes, generatorDataToBytes } from "../helpers";
import { GeneratorRegistry__factory, MockToken__factory } from "../typechain-types";
import BigNumber from "bignumber.js";

// Add priv of generator in array. These generators will be registers on market place
const generatorPrivKeys: string[] = [];

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

  const generators = generatorPrivKeys.map((a) => new ethers.Wallet(a, admin.provider));

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    throw new Error("token contract not deployed");
  }

  if (!addresses.proxy.generatorRegistry) {
    throw new Error("generatorRegistry contract not deployed");
  }

  if (!addresses.zkbMarketId) {
    throw new Error("Market not created");
  }

  const generatorRegistry = GeneratorRegistry__factory.connect(addresses.proxy.generatorRegistry, admin);

  const generatorAddress = await Promise.all(generators.map(async (a) => await a.getAddress()));
  console.log("generator Addresses", generatorAddress);

  const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
  for (let index = 0; index < generatorAddress.length; index++) {
    const generator = generators[index];
    let tx = await mockToken.transfer(await generator.getAddress(), "2000000000000000000000");
    console.log("token transfer transaction", (await tx.wait())?.hash);

    const transferTx = await tokenHolder.sendTransaction({
      to: await generator.getAddress(),
      value: "10000000000000000",
    });
    console.log("ethers transfer transaction", (await transferTx.wait())?.hash);

    tx = await mockToken
      .connect(generator)
      .approve(await generatorRegistry.getAddress(), config.generatorStakingAmount);
    console.log("market approval transaction", (await tx.wait())?.hash);

    const generatorData = {
      name: `Generator Index ${index}`,
      time: 10000,
      generatorOysterPubKey: "0x" + bytesToHexString(await generateRandomBytes(64)),
      computeAllocation: 100,
    };
    const geneatorDataString = generatorDataToBytes(generatorData);
    tx = await generatorRegistry.connect(generator).register(await generator.getAddress(), geneatorDataString);
    await tx.wait();
    tx = await generatorRegistry.connect(generator).stake(await generator.getAddress(), config.generatorStakingAmount);
    await tx.wait();
    await generatorRegistry.connect(generator).joinMarketPlace(
      addresses.zkbMarketId,
      new BigNumber(10)
        .pow(19)
        .multipliedBy(index + 1)
        .toFixed(),
      1000,
      index + 1,
    );

    console.log("generator registration transaction", (await tx.wait())?.hash);
  }
  return "Done";
}

main().then(console.log).catch(console.log);
