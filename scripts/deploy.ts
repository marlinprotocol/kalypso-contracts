import { ethers, upgrades } from "hardhat";
import * as fs from "fs";

import {
  GeneratorRegistry__factory,
  MockToken__factory,
  ProofMarketPlace__factory,
  TransferVerifier__factory,
  Transfer_verifier_wrapper__factory,
} from "../typechain-types";
import { checkFileExists, createFileIfNotExists } from "../helpers";

async function main(): Promise<string> {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

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
  let treasury = signers[2];
  let marketCreator = signers[3];
  let generator = signers[4];
  let matchingEngine = signers[5];

  const path = `./addresses/${chainId}.json`;
  createFileIfNotExists(path);

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mockToken) {
    const mockToken = await new MockToken__factory(admin).deploy(await tokenHolder.getAddress(), config.tokenSupply);
    await mockToken.waitForDeployment();
    addresses.proxy.mockToken = await mockToken.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.generatorRegistry) {
    const GeneratorRegistryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(GeneratorRegistryContract, [], {
      kind: "uups",
      constructorArgs: [addresses.proxy.mockToken, config.generatorStakingAmount, config.generatorSlashingPenalty],
      initializer: false,
    });
    await generatorProxy.waitForDeployment();

    addresses.proxy.generatorRegistry = await generatorProxy.getAddress();
    addresses.implementation.generatorRegistry = await upgrades.erc1967.getImplementationAddress(
      addresses.proxy.generatorRegistry,
    );
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.proofMarketPlace) {
    const ProofMarketPlace = await ethers.getContractFactory("ProofMarketPlace");
    const proxy = await upgrades.deployProxy(
      ProofMarketPlace,
      [
        await admin.getAddress(),
        addresses.proxy.mockToken,
        await treasury.getAddress(),
        config.marketCreationCost,
        addresses.proxy.generatorRegistry,
      ],
      { kind: "uups", constructorArgs: [] },
    );
    await proxy.waitForDeployment();

    addresses.proxy.proofMarketPlace = await proxy.getAddress();
    addresses.implementation.proofMarketPlace = await upgrades.erc1967.getImplementationAddress(
      addresses.proxy.proofMarketPlace,
    );
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  const generatorRegistry = GeneratorRegistry__factory.connect(addresses.proxy.generatorRegistry, admin);
  const tx = await generatorRegistry.initialize(await admin.getAddress(), addresses.proxy.proofMarketPlace);
  await tx.wait();

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.transferVerifierWrapper) {
    const TransferVerifer = await new TransferVerifier__factory(admin).deploy();
    await TransferVerifer.waitForDeployment();
    const TransferVerifierWrapper = await new Transfer_verifier_wrapper__factory(admin).deploy(
      await TransferVerifer.getAddress(),
    );
    await TransferVerifierWrapper.waitForDeployment();
    addresses.proxy.transferVerifierWrapper = await TransferVerifierWrapper.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, matchingEngine);
  await (
    await proofMarketPlace
      .connect(admin)
      .grantRole(await proofMarketPlace.MATCHING_ENGINE_ROLE(), await matchingEngine.getAddress())
  ).wait();

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  return "done";
}

main().then(console.log).catch(console.log);
