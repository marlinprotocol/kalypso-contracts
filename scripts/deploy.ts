import { ethers, upgrades } from "hardhat";
import * as fs from "fs";

import {
  GeneratorRegistry__factory,
  InputAndProofFormatRegistry__factory,
  MockAttestationVerifier__factory,
  MockToken__factory,
  PriorityLog__factory,
  EntityKeyRegistry__factory,
  AttestationVerifier__factory,
  Dispute__factory,
} from "../typechain-types";
import { checkFileExists, createFileIfNotExists } from "../helpers";

import * as transfer_verifier_inputs from "../helpers/sample/transferVerifier/transfer_inputs.json";
import * as transfer_verifier_proof from "../helpers/sample/transferVerifier/transfer_proof.json";

import * as zkb_verifier_inputs from "../helpers/sample/zkbVerifier/transfer_input.json";
import * as zkb_verifier_proof from "../helpers/sample/zkbVerifier/transfer_proof.json";

const abiCoder = new ethers.AbiCoder();

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
  let sampleSigner = signers[5];

  const path = `./addresses/${chainId}.json`;
  createFileIfNotExists(path);

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses.proxy.payment_token) {
    const payment_token = await new MockToken__factory(admin).deploy(
      await tokenHolder.getAddress(),
      config.tokenSupply,
      "Payment Token",
      "PT",
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
      "Staking Token",
      "ST",
    );
    await staking_token.waitForDeployment();
    addresses.proxy.staking_token = await staking_token.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.mock_attestation_verifier) {
    const mock_attestation_verifier = await new MockAttestationVerifier__factory(admin).deploy();
    await mock_attestation_verifier.waitForDeployment();

    addresses.proxy.mock_attestation_verifier = await mock_attestation_verifier.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.attestation_verifier) {
    const attestationVerifierFactory = await ethers.getContractFactory("AttestationVerifier");
    const attestationVerifierProxy = await upgrades.deployProxy(attestationVerifierFactory, [], {
      kind: "uups",
      constructorArgs: [],
      initializer: false,
    });
    await attestationVerifierProxy.waitForDeployment();

    addresses.proxy.attestation_verifier = await attestationVerifierProxy.getAddress();
    addresses.implementation.attestation_verifier = await upgrades.erc1967.getImplementationAddress(addresses.proxy.attestation_verifier);
    const attestation_verifier = AttestationVerifier__factory.connect(addresses.proxy.attestation_verifier, admin);
    const tx = await attestation_verifier.initialize(
      [
        {
          PCR0: "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
          PCR1: "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          PCR2: "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003",
        },
      ],
      ["0x0000000000000000000000000000000000000001"],
      await admin.getAddress(),
    );
    await tx.wait();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.entity_registry) {
    const EntityKeyRegistryContract = await ethers.getContractFactory("EntityKeyRegistry");
    const _entityKeyRegistry = await upgrades.deployProxy(EntityKeyRegistryContract, [await admin.getAddress(), []], {
      kind: "uups",
      constructorArgs: [addresses.proxy.attestation_verifier],
    });
    await _entityKeyRegistry.waitForDeployment();
    const entity_registry = EntityKeyRegistry__factory.connect(await _entityKeyRegistry.getAddress(), admin);

    addresses.proxy.entity_registry = await entity_registry.getAddress();
    addresses.implementation.entity_registry = await upgrades.erc1967.getImplementationAddress(addresses.proxy.entity_registry);
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.generator_registry) {
    const generator_registryContract = await ethers.getContractFactory("GeneratorRegistry");
    const generatorProxy = await upgrades.deployProxy(generator_registryContract, [], {
      kind: "uups",
      constructorArgs: [addresses.proxy.staking_token, addresses.proxy.entity_registry],
      initializer: false,
    });

    await generatorProxy.waitForDeployment();

    addresses.proxy.generator_registry = await generatorProxy.getAddress();
    addresses.implementation.generator_registry = await upgrades.erc1967.getImplementationAddress(addresses.proxy.generator_registry);
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    const entityRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entity_registry, admin);
    const roleToGive = await entityRegistry.KEY_REGISTER_ROLE();
    let tx = await entityRegistry.grantRole(roleToGive, addresses.proxy.generator_registry);
    tx.wait();
  }
  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses.proxy.dispute) {
    const dispute = await new Dispute__factory(admin).deploy(addresses.proxy.entity_registry);
    await dispute.waitForDeployment();
    addresses.proxy.dispute = await dispute.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.proxy.proof_market_place) {
    const proof_market_place = await ethers.getContractFactory("ProofMarketplace");
    const proxy = await upgrades.deployProxy(proof_market_place, [await admin.getAddress()], {
      kind: "uups",
      constructorArgs: [
        addresses.proxy.payment_token,
        config.marketCreationCost,
        await treasury.getAddress(),
        addresses.proxy.generator_registry,
        addresses.proxy.entity_registry,
      ],
    });
    await proxy.waitForDeployment();

    addresses.proxy.proof_market_place = await proxy.getAddress();
    addresses.implementation.proof_market_place = await upgrades.erc1967.getImplementationAddress(addresses.proxy.proof_market_place);
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    const entityRegistry = EntityKeyRegistry__factory.connect(addresses.proxy.entity_registry, admin);
    const roleToGive = await entityRegistry.KEY_REGISTER_ROLE();
    let tx = await entityRegistry.grantRole(roleToGive, addresses.proxy.proof_market_place);
    tx.wait();

    const generator_registry = GeneratorRegistry__factory.connect(addresses.proxy.generator_registry, admin);
    tx = await generator_registry.initialize(await admin.getAddress(), addresses.proxy.proof_market_place);
    await tx.wait();
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
    const input_and_proof_format = await new InputAndProofFormatRegistry__factory(admin).deploy(await admin.getAddress());
    await input_and_proof_format.waitForDeployment();

    addresses.proxy.input_and_proof_format = await input_and_proof_format.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8")); // for next steps
  return "done";
}

main().then(console.log).catch(console.log);
