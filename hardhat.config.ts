import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-chai-matchers";

import "hardhat-gas-reporter";

import { config as dotenvConfig } from "dotenv";

import BigNumber from "bignumber.js";

dotenvConfig();

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  const provider = hre.ethers.provider;

  for (const account of accounts) {
    console.log(
      "%s (%i ETH)",
      account.address,
      new BigNumber((await provider.getBalance(account.address)).toString())
        .dividedBy(new BigNumber(10).pow(18))
        .toFixed(4),
    );
  }
});

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{ version: "0.8.19" }, { version: "0.6.12" }],
  },
  gasReporter: {
    enabled: true,
    gasPrice: 1,
    coinmarketcap: process.env.COIN_MARKET_CAP,
  },
  networks: {
    hardhat: {
      blockGasLimit: 500000000000,
    },
  },
};

export default config;
