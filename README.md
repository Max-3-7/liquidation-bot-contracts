## TraderJoe Liquidator

Bot to automatically liquidate undercollaterazed TraderJoe accounts.

Rinkeby contract address : [0x931dCCD87F217BEd0697b555350fd6fE0B5E3B2a](https://rinkeby.etherscan.io/address/0x931dCCD87F217BEd0697b555350fd6fE0B5E3B2a)

## Installation

```
npm install
yarn
```

## Run tests

```
npx hardhat test
```

## Contract deployment

Deploy to testnet

```
npx hardhat --network rinkeby run scripts/deploy.ts
```

Deploy to Avalanche mainnet

```
npx hardhat --network mainnet run scripts/deploy.ts
```

## Configuration

### Environment variables

| ENV Variable      | Description                                                                 |
| ----------------- | --------------------------------------------------------------------------- |
| CONTRACT_DEPLOYER | Avalanche C-Chain address of the account that will execute the liquidations |
| INFURA_API_KEY    | Infura API KEY                                                              |

## Resources

- https://github.com/ava-labs/avalanche-smart-contract-quickstart
