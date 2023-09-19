import { ethers } from "hardhat";
import * as fs from "fs";
import { checkFileExists, marketDataToBytes } from "../helpers";
import { MockToken__factory, ProofMarketPlace__factory } from "../typechain-types";

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

  if (!addresses?.proxy?.zkbVerifierWrapper) {
    throw new Error("zkbVerifierWrapper is not deployed");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.zkbMarketId) {
    const mockToken = MockToken__factory.connect(addresses.proxy.mockToken, tokenHolder);
    await mockToken.connect(tokenHolder).transfer(await marketCreator.getAddress(), config.marketCreationCost);
    await mockToken.connect(marketCreator).approve(await proofMarketPlace.getAddress(), config.marketCreationCost);

    const marketSetupData = {
      zkAppName: "zkbob arb sepolia",
      proverCode: "url of the zkbob prover code",
      verifierCode: "url of the verifier zkbob code",
      proverOysterImage: "oyster image link for the zkbob prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
    };

    const marketSetupBytes = marketDataToBytes(marketSetupData);
    const zkbMarketId = ethers.keccak256(marketDataToBytes(marketSetupData));

    const tx = await proofMarketPlace
      .connect(marketCreator)
      .createMarketPlace(marketSetupBytes, addresses.proxy.zkbVerifierWrapper);
    await tx.wait();
    addresses.zkbMarketId = zkbMarketId;
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  return "Done";
}

main().then(console.log).catch(console.log);
