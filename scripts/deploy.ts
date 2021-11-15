import { Contract, ContractFactory } from 'ethers'
import { ethers } from 'hardhat'

// npx hardhat --network fuji run scripts/deploy.ts

const main = async (): Promise<any> => {
  const TraderJoeLiquidator: ContractFactory = await ethers.getContractFactory('TraderJoeLiquidator')
  const traderJoeLiquidator: Contract = await TraderJoeLiquidator.deploy({ gasLimit: 400000 })
  await traderJoeLiquidator.deployed()
  console.log(`TraderJoeLiquidator deployed to: ${traderJoeLiquidator.address}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
