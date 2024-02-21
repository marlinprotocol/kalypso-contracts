import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-chai-matchers";

import "hardhat-gas-reporter";
import "solidity-coverage";

import { config as dotenvConfig } from "dotenv";

import BigNumber from "bignumber.js";

dotenvConfig();

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  const provider = hre.ethers.provider;

  for (const account of accounts) {
    console.log("%s (%i wei)", account.address, new BigNumber((await provider.getBalance(account.address)).toString()));
  }
});

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  gasReporter: {
    enabled: true,
    gasPrice: 1,
    coinmarketcap: process.env.COIN_MARKET_CAP,
  },
  etherscan: {
    apiKey: {
      mainnet: `${process.env.ETHERSCAN_API_KEY}`,
      arbSepolia: `${process.env.ARB_SEPOLIA_API_KEY}`,
    },
    customChains: [
      {
        network: "arbSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io/",
        },
      },
    ],
  },
  networks: {
    hardhat: {
      blockGasLimit: 500000000000,
    },
    sepolia: {
      url: `${process.env.SEPOLIA_RPC_URL}`,
      // NOTE: don't change the order of elements in the array, add new elements at the last.
      accounts: [
        `${process.env.SEPOLIA_ADMIN}`,
        `${process.env.SEPOLIA_TOKEN_HOLDER}`,
        `${process.env.SEPOLIA_TREASURY}`,
        `${process.env.SEPOLIA_MARKET_CREATOR}`,
        `${process.env.SEPOLIA_GENERATOR}`,
        `${process.env.SEPOLIA_MATCHING_ENGINE}`,
        `${process.env.SEPOLIA_PROOF_REQUESTOR}`,
      ],
    },
    arbSepolia: {
      url: `${process.env.ARB_SEPOLIA_RPC_URL}`,
      accounts: [
        `${process.env.SEPOLIA_ADMIN}`,
        `${process.env.SEPOLIA_TOKEN_HOLDER}`,
        `${process.env.SEPOLIA_TREASURY}`,
        `${process.env.SEPOLIA_MARKET_CREATOR}`,
        `${process.env.SEPOLIA_GENERATOR}`,
        `${process.env.SEPOLIA_MATCHING_ENGINE}`,
        `${process.env.SEPOLIA_PROOF_REQUESTOR}`,
      ],
    },
    nova: {
      url: `${process.env.NOVA_RPC_URL}`,
      accounts: [
        `${process.env.NOVA_ADMIN}`,
        `${process.env.NOVA_TOKEN_HOLDER}`,
        `${process.env.NOVA_TREASURY}`,
        `${process.env.NOVA_MARKET_CREATOR}`,
        `${process.env.NOVA_GENERATOR}`,
        `${process.env.NOVA_MATCHING_ENGINE}`,
        `${process.env.NOVA_PROOF_REQUESTOR}`,
      ],
    },
  },
};

export default config;
