import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists, marketDataToBytes } from "../helpers";
import {
  MockToken__factory,
  ProofMarketPlace__factory,
  Xor2_verifier_wrapper__factory,
  XorVerifier__factory,
} from "../typechain-types";

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
  let tokenHolder = signers[1];
  let marketCreator = signers[3];

  const path = `./addresses/${chainId}.json`;
  const addressesExists = checkFileExists(path);

  if (!addressesExists) {
    throw new Error(`Address file doesn't exists for ChainId: ${chainId}`);
  }

  let addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  if (!addresses?.proxy?.proofMarketPlace) {
    throw new Error("Proof Market Place Is Not Deployed");
  }
  const proofMarketPlace = ProofMarketPlace__factory.connect(addresses.proxy.proofMarketPlace, marketCreator);

  if (!addresses?.proxy?.mockToken) {
    throw new Error("Mock Token Is Not Deployed");
  }

  if (!addresses.proxy.circomVerifierWrapper) {
    const ciromVerifier = await new XorVerifier__factory(marketCreator).deploy();
    await ciromVerifier.waitForDeployment();

    const ciromVerifierWrapper = await new Xor2_verifier_wrapper__factory(marketCreator).deploy(
      await ciromVerifier.getAddress(),
    );
    await ciromVerifierWrapper.waitForDeployment();

    addresses.proxy.circomVerifierWrapper = await ciromVerifierWrapper.getAddress();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.circomMarketId) {
    const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), config.marketCreationCost);
    await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), config.marketCreationCost);

    const marketSetupData = {
      zkAppName: "circom verifier",
      proverCode: "url of the prover code",
      verifierCode: "url of the verifier code",
      proverOysterImage: "oyster image link for the prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
    };

    const marketSetupBytes = marketDataToBytes(marketSetupData);
    const circomMarketId = ethers.keccak256(marketDataToBytes(marketSetupData));

    const tx = await proofMarketPlace
      .connect(marketCreator)
      .createMarketPlace(marketSetupBytes, addresses.proxy.circomVerifierWrapper);
    await tx.wait();
    addresses.circomMarketId = circomMarketId;
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  return "Done";
}

main().then(console.log).catch(console.log);
