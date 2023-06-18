import "@nomiclabs/hardhat-waffle";
import { HardhatUserConfig } from "hardhat/config";
import { HttpNetworkUserConfig } from "hardhat/types";

import "@typechain/hardhat";
import "hardhat-deploy";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";

// dynamically changes endpoints for local tests
const zkSyncTestnet =
  process.env.NODE_ENV == "test"
    ? {
        url: "http://localhost:3050",
        ethNetwork: "http://localhost:8545",
        zksync: true,
      }
    : {
        url: "https://testnet.era.zksync.dev",
        ethNetwork: "goerli",
        zksync: true,
        verifyURL: 'https://testnet-explorer.zksync.dev/contract_verification'
      };

module.exports = {
  
  zksolc: {
    version: "1.3.5",
    compilerSource: "binary",
    settings: {},
  },
  defaultNetwork: "localhost",


  networks: {
    hardhat: {
    },
    // load test network details
    zkSyncTestnet,
  },
  solidity: {
    version: "0.8.17",
  },
};
