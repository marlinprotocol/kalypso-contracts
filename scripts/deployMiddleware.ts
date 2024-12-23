import { ethers, upgrades, run } from "hardhat";
import * as fs from "fs";

import { Middleware__factory } from "../typechain-types";
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
        throw new Error("Attestation Verifier not deployed");
    }

    if (!addresses.proxy.middleware) {
        const middlewareFactory = (await ethers.getContractFactory("Middleware", admin)) as Middleware__factory;

        const proxy = await upgrades.deployProxy(
            middlewareFactory.connect(deployer),
            [config.symbiotic.networkId, addresses.proxy.attestation_verifier, await admin.getAddress()],
            { initializer: "initialize" }
        );
        await proxy.waitForDeployment();

        addresses.proxy.middleware = await proxy.getAddress();
        addresses.implementation.middleware = await upgrades.erc1967.getImplementationAddress(addresses.proxy.middleware);
        fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

        // verify the contract
        await run("verify:verify", {
            address: addresses.proxy.middleware,
            constructorArguments: [],
        });
    }
    return "Added Middleware";
}

export async function upgrade() {
    let chainId = parseInt((await ethers.provider.getNetwork()).chainId.toString());
    console.log("Chain Id:", chainId);

    const path = `./addresses/${chainId}.json`;

    let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

    if(addresses.proxy === undefined ||
        addresses.proxy.middleware === undefined
    ) {
        console.log("Missing dependencies");
        return;
    }

    let signers = await ethers.getSigners();
    let addrs = await Promise.all(signers.map(a => a.getAddress()));

    console.log("Signer addrs:", addrs);

    let admin = signers[0];
    const CF = await ethers.getContractFactory("Middleware", admin);
    let c = await upgrades.upgradeProxy(addresses.proxy.middleware, CF, { 
        kind: "uups",
        constructorArgs: []
    });
    addresses.implementation.middleware = await upgrades.erc1967.getImplementationAddress(addresses.proxy.middleware);
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");

    // verify the contract
    await run("verify:verify", {
        address: addresses.proxy.middleware,
        constructorArguments: [],
    });

    console.log("Contract upgraded:", c.address);
}

main().then(console.log).catch(console.log);