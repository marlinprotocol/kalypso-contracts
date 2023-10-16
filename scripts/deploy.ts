import { ethers, upgrades } from "hardhat";
import * as fs from "fs";

import {
  GeneratorRegistry__factory,
  InputAndProofFormatRegistry__factory,
  MockAttestationVerifier__factory,
  MockToken__factory,
  PriorityLog__factory,
  ProofMarketPlace__factory,
  EntityKeyRegistry__factory,
  TransferVerifier__factory,
  Transfer_verifier_wrapper__factory,
  ZkbVerifier__factory,
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
  // let marketCreator = signers[3];
  // let generator = signers[4];
  let matchingEngine = signers[5];

  const path = `./addresses/${chainId}.json`;
  createFileIfNotExists(path);

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses.proxy.payment_token) {
    const payment_token = await new MockToken__factory(admin).deploy(
      await tokenHolder.getAddress(),
      config.tokenSupply,
    );
    await payment_token.waitForDeployment();
    addresses.proxy.payment_token = await payment_token.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.staking_token) {
    const staking_token = await new MockToken__factory(admin).deploy(
      await tokenHolder.getAddress(),
      config.tokenSupply,
    );
    await staking_token.waitForDeployment();
    addresses.proxy.staking_token = await staking_token.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.generator_registry) {
    const generator_registryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(generator_registryContract, [], {
      kind: "uups",
      constructorArgs: [addresses.proxy.staking_token],
      initializer: false,
    });
    await generatorProxy.waitForDeployment();

    addresses.proxy.generator_registry = await generatorProxy.getAddress();
    addresses.implementation.generator_registry = await upgrades.erc1967.getImplementationAddress(
      addresses.proxy.generator_registry,
    );
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.attestation_verifier) {
    const attestation_verifier = await new MockAttestationVerifier__factory(admin).deploy();
    await attestation_verifier.waitForDeployment();

    addresses.proxy.attestation_verifier = await attestation_verifier.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.entity_registry) {
    const entity_registry = await new EntityKeyRegistry__factory(admin).deploy(addresses.proxy.attestation_verifier);
    await entity_registry.waitForDeployment();

    addresses.proxy.entity_registry = await entity_registry.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.proof_market_place) {
    const proof_market_place = await ethers.getContractFactory("ProofMarketPlace");
    const proxy = await upgrades.deployProxy(proof_market_place, [await admin.getAddress()], {
      kind: "uups",
      constructorArgs: [
        addresses.proxy.payment_token,
        addresses.proxy.staking_token,
        config.marketCreationCost,
        await treasury.getAddress(),
        addresses.proxy.generator_registry,
        addresses.proxy.entity_registry,
      ],
    });
    await proxy.waitForDeployment();

    addresses.proxy.proof_market_place = await proxy.getAddress();
    addresses.implementation.proof_market_place = await upgrades.erc1967.getImplementationAddress(
      addresses.proxy.proof_market_place,
    );
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    const generator_registry = GeneratorRegistry__factory.connect(addresses.proxy.generator_registry, admin);
    const tx = await generator_registry.initialize(await admin.getAddress(), addresses.proxy.proof_market_place);
    await tx.wait();
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.transfer_verifier_wrapper) {
    const TransferVerifer = await new TransferVerifier__factory(admin).deploy();
    await TransferVerifer.waitForDeployment();
    const transfer_verifier_wrapper = await new Transfer_verifier_wrapper__factory(admin).deploy(
      await TransferVerifer.getAddress(),
    );
    await transfer_verifier_wrapper.waitForDeployment();
    addresses.proxy.transfer_verifier_wrapper = await transfer_verifier_wrapper.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.zkb_verifier_wrapper) {
    const ZkbVerifier = await new ZkbVerifier__factory(admin).deploy();
    await ZkbVerifier.waitForDeployment();
    const zkb_verifier_wrapper = await new Transfer_verifier_wrapper__factory(admin).deploy(
      await ZkbVerifier.getAddress(),
    );
    await zkb_verifier_wrapper.waitForDeployment();
    addresses.proxy.zkb_verifier_wrapper = await zkb_verifier_wrapper.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }
  const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, matchingEngine);
  const hasMatchingEngineRole = await proof_market_place.hasRole(
    await proof_market_place.MATCHING_ENGINE_ROLE(),
    await matchingEngine.getAddress(),
  );
  if (!hasMatchingEngineRole) {
    await (
      await proof_market_place
        .connect(admin)
        ["grantRole(bytes32,address,bytes)"](
          await proof_market_place.MATCHING_ENGINE_ROLE(),
          await matchingEngine.getAddress(),
          "0x",
        )
    ).wait();
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.priority_list) {
    const priority_list = await new PriorityLog__factory(admin).deploy();
    await priority_list.waitForDeployment();
    addresses.proxy.priority_list = await priority_list.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.input_and_proof_format) {
    const input_and_proof_format = await new InputAndProofFormatRegistry__factory(admin).deploy(
      await admin.getAddress(),
    );
    await input_and_proof_format.waitForDeployment();

    addresses.proxy.input_and_proof_format = await input_and_proof_format.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8")); // for next steps
  return "done";
}

main().then(console.log).catch(console.log);
