const { expect } = require('chai')
const { pow } = require('./util.js')
const { ethers, artifacts } = require('hardhat')
const { time } = require('@openzeppelin/test-helpers')
const Web3 = require('web3')
const BN = require('bn.js')
const IERC20 = artifacts.require('IERC20')
const JCollateralCapErc20 = artifacts.require('JCollateralCapErc20')
const Joetroller = artifacts.require('Joetroller')
const PriceOracle = artifacts.require('PriceOracle')
const JToken = artifacts.require('JToken')

describe('TraderJoeLiquidator', function () {
  const USDC_WHALE = '0x2d1944bD960CDE5d8b14E5f8093d9E017f4Ce5A8'
  const WAVAX_WHALE = '0xda6ad74619e62503C4cbefbE02aE05c8F4314591'
  const WETH_WHALE = '0x77e4ff5564a36be56c23039278ab76b784e0e9f0'

  const JOETROLLER = '0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC'
  const PRICE_ORACLE = '0xe34309613B061545d42c4160ec4d64240b114482'

  const USDC = '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664'
  const USDC_DECIMALS = 6

  const jUSDC = '0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC'
  const jUSDC_DECIMALS = 8

  const jAVAX = '0xC22F01ddc8010Ee05574028528614634684EC29e'
  const jAVAX_DECIMALS = 8

  const WAVAX = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7'
  const WAVAX_DECIMALS = 18

  const jWETH = '0x929f5caB61DFEc79a5431a7734a68D714C4633fa'
  const jWETH_DECIMALS = 8

  const WETH = '0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB'
  const WETH_DECIMALS = 18

  const jDAI = '0xc988c170d0E38197DC634A45bF00169C7Aa7CA19'
  const jDAI_DECIMALS = 8

  const DAI = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70'
  const DAI_DECIMALS = 18

  const jUSDT = '0x8b650e26404AC6837539ca96812f0123601E4448'
  const jUSDT_DECIMALS = 8

  const USDT = '0xc7198437980c041c805A1EDcbA50c1Ce5db95118'
  const USDT_DECIMALS = 6

  describe('Liquidations', function () {
    let signersIndex = 0

    let TraderJoeLiquidator
    let traderJoeLiquidator

    let joetroller
    let jUSDCtoken
    let usdcToken
    let jAVAXToken
    let wavaxToken
    let wethToken
    let jWETHToken
    let jDAIToken
    let jUSDTToken

    before(async function () {
      TraderJoeLiquidator = await ethers.getContractFactory('TraderJoeLiquidator')
    })

    beforeEach(async function () {
      traderJoeLiquidator = await TraderJoeLiquidator.deploy()
      await traderJoeLiquidator.deployed()

      joetroller = await Joetroller.at(JOETROLLER)
      jUSDCtoken = await JCollateralCapErc20.at(jUSDC)
      usdcToken = await IERC20.at(USDC)
      jAVAXToken = await JCollateralCapErc20.at(jAVAX)
      wavaxToken = await IERC20.at(WAVAX)
      wethToken = await IERC20.at(WETH)
      jWETHToken = await JCollateralCapErc20.at(jWETH)
      jDAIToken = await JCollateralCapErc20.at(jDAI)
      jUSDTToken = await JCollateralCapErc20.at(jUSDT)

      // impersonate whales
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [USDC_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [WAVAX_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [WETH_WHALE],
      })
      // set balance to cover gas
      await network.provider.send('hardhat_setBalance', [USDC_WHALE, '0x6750000000000000000000000'])
      await network.provider.send('hardhat_setBalance', [WAVAX_WHALE, '0x6750000000000000000000000'])
      await network.provider.send('hardhat_setBalance', [WETH_WHALE, '0x6750000000000000000000000'])
    })

    afterEach(async function () {
      // stop impersonating whales
      await hre.network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [USDC_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [WAVAX_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [WETH_WHALE],
      })
    })

    it('should repay USDC and seize AVAX', async () => {
      const BORROWER = await initializeFreshAccount()

      // fund borrower
      const supplyAmount = new BN(10).pow(new BN(WAVAX_DECIMALS)).muln(50)
      await wavaxToken.transfer(BORROWER, supplyAmount, { from: WAVAX_WHALE })

      // mint jAVAX
      await wavaxToken.approve(jAVAXToken.address, supplyAmount, { from: BORROWER })
      await jAVAXToken.mint(supplyAmount, { from: BORROWER })

      // enter market
      await joetroller.enterMarkets([jAVAXToken.address], { from: BORROWER })

      // borrow
      const avaxPriceUSD = await getAssetPriceInUSD(jAVAX, WAVAX_DECIMALS)
      console.log('Avax price', avaxPriceUSD)
      const supplyValueUSD = (avaxPriceUSD * supplyAmount) / pow(10, WAVAX_DECIMALS)
      console.log('Supply value USD', supplyValueUSD)
      const borrowAmount = supplyValueUSD * pow(10, USDC_DECIMALS) * 0.75 * (9999 / 10000) // NOTES : adjust ratio to have account with positive shortfall
      console.log('Borrow amount', borrowAmount)
      await jUSDCtoken.borrow(Math.trunc(borrowAmount), { from: BORROWER })

      // accrue interest on borrow
      const block = await web3.eth.getBlockNumber()
      // NOTE : adjust block number to have account with positive shortfall
      await time.advanceBlockTo(block + 50000)

      await traderJoeLiquidator.liquidate(BORROWER, jUSDCtoken.address, jAVAXToken.address)

      const expectedProfitInUSDC = Math.trunc(borrowAmount / 2) * 0.065
      expect(Number(await usdcToken.balanceOf(traderJoeLiquidator.address))).to.be.at.least(expectedProfitInUSDC)
    })

    it('should repay AVAX and seize AVAX', async () => {
      const BORROWER = await initializeFreshAccount()

      // fund borrower
      const supplyAmount = new BN(10).pow(new BN(WAVAX_DECIMALS)).muln(50)
      await wavaxToken.transfer(BORROWER, supplyAmount, { from: WAVAX_WHALE })

      // mint jAVAX
      await wavaxToken.approve(jAVAXToken.address, supplyAmount, { from: BORROWER })
      await jAVAXToken.mint(supplyAmount, { from: BORROWER })

      // enter market
      await joetroller.enterMarkets([jAVAXToken.address], { from: BORROWER })

      // borrow AVAX
      const borrowAmount = supplyAmount.muln(0.75)
      await jAVAXToken.borrow(borrowAmount, { from: BORROWER })

      // accrue interest on borrow
      const block = await web3.eth.getBlockNumber()
      // NOTE : adjust block number to have account with positive shortfall
      await time.advanceBlockTo(block + 50000)

      await traderJoeLiquidator.liquidate(BORROWER, jAVAXToken.address, jAVAXToken.address)
    })

    it('should repay DAI and seize WETH', async () => {
      const BORROWER = await initializeFreshAccount()

      // fund borrower
      const supplyAmount = new BN(10).pow(new BN(WETH_DECIMALS)).muln(10)
      await wethToken.transfer(BORROWER, supplyAmount, { from: WETH_WHALE })

      // mint jWETH
      await wethToken.approve(jWETHToken.address, supplyAmount, { from: BORROWER })
      await jWETHToken.mint(supplyAmount, { from: BORROWER })

      // enter market
      await joetroller.enterMarkets([jWETHToken.address], { from: BORROWER })

      // borrow DAI
      const wethPriceUSD = await getAssetPriceInUSD(jWETH, WETH_DECIMALS)
      const supplyValueUSD = (wethPriceUSD * supplyAmount) / pow(10, WETH_DECIMALS)
      const borrowAmount = new BN(supplyValueUSD)
        .mul(new BN(10).pow(new BN(DAI_DECIMALS)))
        .muln(0.75)
        .muln(9991 / 10000) // NOTES : adjust ratio to have account with positive shortfall
      console.log('Borrow amount', borrowAmount.toString())
      await jDAIToken.borrow(borrowAmount, { from: BORROWER })

      // accrue interest on borrow
      const block = await web3.eth.getBlockNumber()
      // NOTE : adjust block number to have account with positive shortfall
      await time.advanceBlockTo(block + 50000)

      await traderJoeLiquidator.liquidate(BORROWER, jDAIToken.address, jWETHToken.address)
    })

    it('should repay USDT and seize AVAX', async () => {
      const BORROWER = await initializeFreshAccount()

      // fund borrower
      const supplyAmount = new BN(10).pow(new BN(WAVAX_DECIMALS)).muln(50)
      await wavaxToken.transfer(BORROWER, supplyAmount, { from: WAVAX_WHALE })

      // mint jAVAX
      await wavaxToken.approve(jAVAXToken.address, supplyAmount, { from: BORROWER })
      await jAVAXToken.mint(supplyAmount, { from: BORROWER })

      // enter market
      await joetroller.enterMarkets([jAVAXToken.address], { from: BORROWER })

      // borrow
      const avaxPriceUSD = await getAssetPriceInUSD(jAVAX, WAVAX_DECIMALS)
      console.log('Avax price', avaxPriceUSD)
      const supplyValueUSD = (avaxPriceUSD * supplyAmount) / pow(10, WAVAX_DECIMALS)
      console.log('Supply value USD', supplyValueUSD)
      const borrowAmount = supplyValueUSD * pow(10, USDT_DECIMALS) * 0.75 * (9997 / 10000) // NOTES : adjust ratio to have account with positive shortfall
      console.log('Borrow amount', borrowAmount)
      await jUSDTToken.borrow(Math.trunc(borrowAmount), { from: BORROWER })

      // accrue interest on borrow
      const block = await web3.eth.getBlockNumber()
      // NOTE : adjust block number to have account with positive shortfall
      await time.advanceBlockTo(block + 50000)

      await traderJoeLiquidator.liquidate(BORROWER, jUSDTToken.address, jAVAXToken.address)
    })

    async function initializeFreshAccount() {
      const accounts = await hre.ethers.getSigners()
      const borrower = accounts[signersIndex].address
      await network.provider.send('hardhat_setBalance', [borrower, '0x6750000000000000000000000'])
      signersIndex += 1
      return borrower
    }

    async function getAssetPriceInUSD(asset, decimals) {
      const priceOracle = await PriceOracle.at(PRICE_ORACLE)
      const price = await priceOracle.getUnderlyingPrice(asset)
      return price / pow(10, decimals)
    }
  })
})
