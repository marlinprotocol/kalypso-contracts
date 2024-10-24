import '@nomicfoundation/hardhat-toolbox';
import '@openzeppelin/hardhat-upgrades';
import '@nomicfoundation/hardhat-chai-matchers';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

import BigNumber from 'bignumber.js';
import { config as dotenvConfig } from 'dotenv';
import {
  HardhatUserConfig,
  task,
} from 'hardhat/config';

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
        version: "0.8.26",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.24",
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
      holesky: `${process.env.HOLESKY_API_KEY}`,
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
      {
        network: "holesky",
        chainId: 17000,
        urls: {
          apiURL: "https://api-holesky.etherscan.io/api",
          browserURL: "https://holesky.etherscan.io/",
        },
      }
    ],
  },
  networks: {
    hardhat: {
      blockGasLimit: 500000000000,
    },
    holesky: {
      url: `${process.env.HOLESKY_RPC_URL}`,
      accounts: [
        `${process.env.HOLESKY_ADMIN}`,
        `${process.env.HOLESKY_DEPLOYER}`,
      ],
    },
    // sepolia: {
    //   url: `${process.env.SEPOLIA_RPC_URL}`,
    //   // NOTE: don't change the order of elements in the array, add new elements at the last.
    //   accounts: [
    //     `${process.env.SEPOLIA_ADMIN}`,
    //     `${process.env.SEPOLIA_TOKEN_HOLDER}`,
    //     `${process.env.SEPOLIA_TREASURY}`,
    //     `${process.env.SEPOLIA_MARKET_CREATOR}`,
    //     `${process.env.SEPOLIA_GENERATOR}`,
    //     `${process.env.SEPOLIA_MATCHING_ENGINE}`,
    //     `${process.env.SEPOLIA_PROOF_REQUESTOR}`,
    //   ],
    // },
    // arbSepolia: {
    //   url: `${process.env.ARB_SEPOLIA_RPC_URL}`,
    //   accounts: [
    //     `${process.env.SEPOLIA_ADMIN}`,
    //     `${process.env.SEPOLIA_TOKEN_HOLDER}`,
    //     `${process.env.SEPOLIA_TREASURY}`,
    //     `${process.env.SEPOLIA_MARKET_CREATOR}`,
    //     `${process.env.SEPOLIA_GENERATOR}`,
    //     `${process.env.SEPOLIA_MATCHING_ENGINE}`,
    //     `${process.env.SEPOLIA_PROOF_REQUESTOR}`,
    //   ],
    // },
    // nova: {
    //   url: `${process.env.NOVA_RPC_URL}`,
    //   accounts: [
    //     `${process.env.NOVA_ADMIN}`,
    //     `${process.env.NOVA_TOKEN_HOLDER}`,
    //     `${process.env.NOVA_TREASURY}`,
    //     `${process.env.NOVA_MARKET_CREATOR}`,
    //     `${process.env.NOVA_GENERATOR}`,
    //     `${process.env.NOVA_MATCHING_ENGINE}`,
    //     `${process.env.NOVA_PROOF_REQUESTOR}`,
    //   ],
    // },
    // zksync: {
    //   url: `${process.env.ZKSYNC_URL}`,
    //   accounts: [
    //     `${process.env.ZKSYNC_ADMIN}`,
    //     `${process.env.ZKSYNC_TOKEN_HOLDER}`,
    //     `${process.env.ZKSYNC_TREASURY}`,
    //     `${process.env.ZKSYNC_MARKET_CREATOR}`,
    //     `${process.env.ZKSYNC_GENERATOR}`,
    //     `${process.env.ZKSYNC_MATCHING_ENGINE}`,
    //     `${process.env.ZKSYNC_PROOF_REQUESTOR}`,
    //   ],
    // },
    // amoy: {
    //   url: `${process.env.AMOY_RPC}`,
    //   accounts: [
    //     `${process.env.AMOY_ADMIN}`,
    //     `${process.env.AMOY_TOKEN_HOLDER}`,
    //     `${process.env.AMOY_TREASURY}`,
    //     `${process.env.AMOY_MARKET_CREATOR}`,
    //     `${process.env.AMOY_GENERATOR}`,
    //     `${process.env.AMOY_MATCHING_ENGINE}`,
    //     `${process.env.AMOY_PROOF_REQUESTOR}`,
    //   ],
    // },
  },
};

export default config;
