import {
  run,
  tenderly,
} from 'hardhat';

import { getConfig } from '../helper';

async function verify(): Promise<string> {
  const { addresses } = await getConfig();

  let verificationResult;

  try {
    // StakingManager
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.stakingManager,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("StakingManager implementation already verified, continuing...");
    } else {
      console.error("Error verifying StakingManager implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.stakingManager,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("StakingManager proxy already verified, continuing...");
    } else {
      console.error("Error verifying StakingManager proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.stakingManager,
      name: "StakingManager",
    });
  } catch (error) {
    console.error("Error verifying StakingManager implementation on Tenderly:", error);
  }
  try {
    await tenderly.verify({
      address: addresses.proxy.stakingManager,
      name: "ERC1967Proxy",
    });
  } catch (error) {
    console.error("Error verifying StakingManager proxy on Tenderly:", error);
  }

  // NativeStaking
  try {
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.nativeStaking,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("NativeStaking implementation already verified, continuing...");
    } else {
      console.error("Error verifying NativeStaking implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.nativeStaking,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("NativeStaking proxy already verified, continuing...");
    } else {
      console.error("Error verifying NativeStaking proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.nativeStaking,
      name: "NativeStaking",
    });
  } catch (error) {
    console.error("Error verifying NativeStaking implementation on Tenderly:", error);
  }

  try {
    await tenderly.verify({
      address: addresses.proxy.nativeStaking,
      name: "NativeStaking",
    });
  } catch (error) {
    console.error("Error verifying NativeStaking proxy on Tenderly:", error);
  }

  // SymbioticStaking
  try {
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.symbioticStaking,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("SymbioticStaking implementation already verified, continuing...");
    } else {
      console.error("Error verifying SymbioticStaking implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.symbioticStaking,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("SymbioticStaking proxy already verified, continuing...");
    } else {
      console.error("Error verifying SymbioticStaking proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.symbioticStaking,
      name: "SymbioticStaking",
    });
  } catch (error) {
    console.error("Error verifying SymbioticStaking implementation on Tenderly:", error);
  }

  try {
    await tenderly.verify({
      address: addresses.proxy.symbioticStaking,
      name: "SymbioticStaking",
    });
  } catch (error) {
    console.error("Error verifying SymbioticStaking proxy on Tenderly:", error);
  }

  // SymbioticStakingReward
  try {
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.symbioticStakingReward,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("SymbioticStakingReward implementation already verified, continuing...");
    } else {
      console.error("Error verifying SymbioticStakingReward implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.symbioticStakingReward,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("SymbioticStakingReward proxy already verified, continuing...");
    } else {
      console.error("Error verifying SymbioticStakingReward proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.symbioticStakingReward,
      name: "SymbioticStakingReward",
    });
  } catch (error) {
    console.error("Error verifying SymbioticStakingReward implementation on Tenderly:", error);
  }

  try {
    await tenderly.verify({
      address: addresses.proxy.symbioticStakingReward,
      name: "SymbioticStakingReward",
    });
  } catch (error) {
    console.error("Error verifying SymbioticStakingReward proxy on Tenderly:", error);
  }

  // ProverManager
  try {
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.proverManager,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("ProverManager implementation already verified, continuing...");
    } else {
      console.error("Error verifying ProverManager implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.proverManager,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("ProverManager proxy already verified, continuing...");
    } else {
      console.error("Error verifying ProverManager proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.proverManager,
      name: "ProverManager",
    });
  } catch (error) {
    console.error("Error verifying ProverManager implementation on Tenderly:", error);
  }

  try {
    await tenderly.verify({
      address: addresses.proxy.proverManager,
      name: "ProverManager",
    });
  } catch (error) {
    console.error("Error verifying ProverManager proxy on Tenderly:", error);
  }

  // ProofMarketplace
  try {
    verificationResult = await run("verify:verify", {
      address: addresses.implementation.proofMarketplace,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("ProofMarketplace implementation already verified, continuing...");
    } else {
      console.error("Error verifying ProofMarketplace implementation:", error);
    }
  }

  try {
    verificationResult = await run("verify:verify", {
      address: addresses.proxy.proofMarketplace,
      constructorArguments: [],
    });
    console.log({ verificationResult });
  } catch (error) {
    if (error) {
      console.log("ProofMarketplace proxy already verified, continuing...");
    } else {
      console.error("Error verifying ProofMarketplace proxy:", error);
    }
  }

  try {
    await tenderly.verify({
      address: addresses.implementation.proofMarketplace,
      name: "ProofMarketplace",
    });
  } catch (error) {
    console.error("Error verifying ProofMarketplace implementation on Tenderly:", error);
  }

  try {
    await tenderly.verify({
      address: addresses.proxy.proofMarketplace,
      name: "ProofMarketplace",
    });
  } catch (error) {
    console.error("Error verifying ProofMarketplace proxy on Tenderly:", error);
  }

  return "Verify Done";
}

verify().then(console.log).catch(console.error);

