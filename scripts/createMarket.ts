import { ethers } from "hardhat";
import * as fs from "fs";
import { MarketData, checkFileExists, marketDataToBytes } from "../helpers";
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

  if (!addresses?.proxy?.proof_market_place) {
    throw new Error("Proof Market Place Is Not Deployed");
  }
  const proof_market_place = ProofMarketPlace__factory.connect(addresses.proxy.proof_market_place, marketCreator);

  if (!addresses?.proxy?.payment_token) {
    throw new Error("payment_token Is Not Deployed");
  }

  if (!addresses?.proxy?.zkb_verifier_wrapper) {
    throw new Error("zkb_verifier_wrapper is not deployed");
  }

  addresses = JSON.parse(fs.readFileSync(path, "utf-8"));
  if (!addresses.zkbMarketId) {
    const payment_token = MockToken__factory.connect(addresses.proxy.payment_token, tokenHolder);
    await payment_token.connect(tokenHolder).transfer(await marketCreator.getAddress(), config.marketCreationCost);
    await payment_token
      .connect(marketCreator)
      .approve(await proof_market_place.getAddress(), config.marketCreationCost);

    const marketSetupData: MarketData = {
      zkAppName: "transfer verifier arb sepolia",
      proverCode: "url of the zkbob prover code",
      verifierCode: "url of the verifier zkbob code",
      proverOysterImage: "oyster image link for the zkbob prover",
      setupCeremonyData: ["first phase", "second phase", "third phase"],
      inputOuputVerifierUrl: "http://localhost:3030/",
    };

    const marketSetupBytes = marketDataToBytes(marketSetupData);
    const zkbMarketId = await proof_market_place.marketCounter();

    const tx = await proof_market_place
      .connect(marketCreator)
      .createMarketPlace(
        marketSetupBytes,
        addresses.proxy.transfer_verifier_wrapper,
        config.generatorSlashingPenalty,
        true,
        "0x",
        Buffer.from(marketSetupData.inputOuputVerifierUrl, "ascii"),
        await marketCreator.getAddress(),
      );
    await tx.wait();
    addresses.zkbMarketId = zkbMarketId.toString();
    fs.writeFileSync(path, JSON.stringify(addresses, null, 4), "utf-8");
  }

  return "Done";
}

main().then(console.log).catch(console.log);
