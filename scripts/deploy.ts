import { Contract, ContractFactory } from 'ethers'
import { ethers, network } from 'hardhat'

// npx hardhat --network rinkeby run scripts/deploy.ts

const main = async (): Promise<any> => {
  const [deployer] = await ethers.getSigners()
  console.log('Deployer', deployer.address)

  const isTestnet = network.name === 'rinkeby'
  const JOETROLLER = isTestnet
    ? '0x5b0a2fa14808e34c5518e19f0dbc39f61d080b11'
    : '0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC'
  const JOEROUTER = isTestnet
    ? '0x7E2528476b14507f003aE9D123334977F5Ad7B14'
    : '0x60aE616a2155Ee3d9A68541Ba4544862310933d4'
  const WAVAX = isTestnet ? '0xc778417E063141139Fce010982780140Aa0cD5Ab' : '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7'
  const USDC = isTestnet ? '0x4DBCdF9B62e891a7cec5A2568C3F4FAF9E8Abe2b' : '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664'
  const JAVAX = isTestnet ? '0xaafe9d8346aefd57399e86d91bbfe256dc0dcac0' : '0xC22F01ddc8010Ee05574028528614634684EC29e'
  const JUSDC = isTestnet ? '0x791C863Fe92CF0472C4DFeAe375E16348971314F' : '0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC'
  const JUSDT = isTestnet ? '0x8b650e26404AC6837539ca96812f0123601E4448' : '0x8b650e26404AC6837539ca96812f0123601E4448' // jUSDT isn't on testnet

  const TraderJoeLiquidator: ContractFactory = await ethers.getContractFactory('TraderJoeLiquidator')
  const traderJoeLiquidator: Contract = await TraderJoeLiquidator.deploy(
    JOETROLLER,
    JOEROUTER,
    WAVAX,
    USDC,
    JAVAX,
    JUSDC,
    JUSDT
  )
  await traderJoeLiquidator.deployed()
  console.log(`TraderJoeLiquidator deployed to: ${traderJoeLiquidator.address}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
