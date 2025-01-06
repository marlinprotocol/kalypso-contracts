import { run } from "hardhat";

import { getConfig } from "../helper";

async function verify(): Promise<string> {
  const { addresses } = await getConfig();

  let verificationResult;

  // StakingManager
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.stakingManager,
    constructorArguments: [],
  });
  console.log({ verificationResult });


  // NativeStaking
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.nativeStaking,
    constructorArguments: [],
  });
  console.log({ verificationResult });
  // SymbioticStaking
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.symbioticStaking,
    constructorArguments: [],
  });
  console.log({ verificationResult });


  // SymbioticStakingReward
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.symbioticStakingReward,
    constructorArguments: [],
  });
  console.log({ verificationResult });


  // ProverManager
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.proverManager,
    constructorArguments: [],
  });
  console.log({ verificationResult });


  // ProofMarketplace
  verificationResult = await run("verify:verify", {
    address: addresses.implementation.proofMarketplace,
    constructorArguments: [],
  });

  console.log({ verificationResult });

  return "Verify Done";
}

verify().then(console.log).catch(console.error);

