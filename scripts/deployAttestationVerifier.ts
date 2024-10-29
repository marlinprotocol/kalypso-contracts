import { ethers, upgrades, run } from "hardhat";
import * as fs from "fs";

import { MockAttestationVerifier__factory } from "../typechain-types";
import { checkFileExists } from "../helpers";

async function main(): Promise<string> {
    const chainId = (await ethers.provider.getNetwork()).chainId.toString();
    console.log("deploying on chain id:", chainId);

    const signers = await ethers.getSigners();
    console.log("available signers", signers.length);

    if (signers.length < 2) {
        throw new Error("Atleast 2 signers are required for deployment");
    }

    const configPath = `./config/${chainId}.json`;
    const configurationExists = checkFileExists(configPath);

    if (!configurationExists) {
        throw new Error(`Config doesn't exists for chainId: ${chainId}`);
    }

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

    let admin = signers[0];
    let deployer = signers[1];

    const path = `./addresses/${chainId}.json`;

    let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

    if (!addresses.proxy.attestation_verifier) {
        const attestationVerifierFactory = (await ethers.getContractFactory("MockAttestationVerifier", admin)) as MockAttestationVerifier__factory;

        const proxy = await upgrades.deployProxy(
            attestationVerifierFactory.connect(deployer),
            []
        );
        await proxy.waitForDeployment();

        addresses.proxy.attestation_verifier = await proxy.getAddress();
        addresses.implementation.attestation_verifier = await upgrades.erc1967.getImplementationAddress(addresses.proxy.attestation_verifier);
        fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

        // verify the contract
        await run("verify:verify", {
            address: addresses.proxy.attestation_verifier,
            constructorArguments: [],
        });
    }
    return "Added AttestationVerifier";
}

main().then(console.log).catch(console.log);