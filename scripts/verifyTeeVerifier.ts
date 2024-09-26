import { run, ethers } from "hardhat";
import { checkFileExists } from "../helpers";
import * as fs from "fs";

async function main() {
  const chainId = (await ethers.provider.getNetwork()).chainId.toString();
  console.log("deploying on chain id:", chainId);

  const signers = await ethers.getSigners();
  console.log("available signers", signers.length);

  let treasury = signers[2];

  if (signers.length < 6) {
    throw new Error("Atleast 6 signers are required for deployment");
  }

  const configPath = `./config/${chainId}.json`;
  const configurationExists = checkFileExists(configPath);

  if (!configurationExists) {
    throw new Error(`Config doesn't exists for chainId: ${chainId}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));

  const path = `./addresses/${chainId}.json`;
  const addresses = JSON.parse(fs.readFileSync(path, "utf-8"));

  let verificationResult;

  verificationResult = await run("verify:verify", {
    address: "0x2cd03e804CD7154f65d3F960caB1d4a8A9B45249",
    constructorArguments: ["0x2f3f64c69b2954CE2f85D1f92A4151Bfc71C78eA", addresses.proxy.attestation_verifier, ["0x000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000030eaea5799ff0a80831010d4b142b3076f5602d6c3d5a0352a93a0ba1a9f4d9439c64a2eafad667e0f9775a479146a83cd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300343b056cd8485ca7890ddd833476d78460aed2aa161548e4e26bedf321726696257d623e8805f3f605946b3d8b0c6aa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030fe23b340165addeac3b051598794eaf566a77b6bdcfbe496e87f8c7f73ef46c5ef0845f9dd87f9244b9b3bf51b100d3a00000000000000000000000000000000"]],
  });
  console.log({ verificationResult });

  return "String";
}

main().then(console.log);
