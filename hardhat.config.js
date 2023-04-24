require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 module.exports = {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
  defaultNetwork: "polygonMumbai",
  networks: {
    hardhat: {
    },
    polygonMumbai: {
      url: '',
      accounts: ['']
    }
  },
  
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      evmVersion: "istanbul"
    }
  },
  mocha: {
    timeout: 40000
  },
  etherscan: {
    apiKey: {
      polygonMumbai: "",
    }
  },
};