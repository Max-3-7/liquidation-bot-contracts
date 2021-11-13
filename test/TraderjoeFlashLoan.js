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

describe('TraderjoeFlashLoan', function () {
  const USDC_WHALE = '0x2d1944bD960CDE5d8b14E5f8093d9E017f4Ce5A8'
  const WAVAX_WHALE = '0xda6ad74619e62503C4cbefbE02aE05c8F4314591'

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

  describe('testFlashLoan', function () {
    let TestTraderJoeFlashLoan
    let testTraderJoeFlashLoan

    let jUSDCtoken
    let usdcToken
    let jAVAXToken
    let wavaxToken

    before(async function () {
      TestTraderJoeFlashLoan = await ethers.getContractFactory('TestTraderJoeFlashLoan')
    })

    beforeEach(async function () {
      testTraderJoeFlashLoan = await TestTraderJoeFlashLoan.deploy()
      await testTraderJoeFlashLoan.deployed()

      jUSDCtoken = await JCollateralCapErc20.at(jUSDC)
      usdcToken = await IERC20.at(USDC)
      jAVAXToken = await JCollateralCapErc20.at(jAVAX)
      wavaxToken = await IERC20.at(WAVAX)

      // impersonate whale
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [USDC_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [WAVAX_WHALE],
      })
      // set balance to cover gas
      await network.provider.send('hardhat_setBalance', [USDC_WHALE, '0x6750000000000000000000000'])
      await network.provider.send('hardhat_setBalance', [WAVAX_WHALE, '0x6750000000000000000000000'])
    })

    afterEach(async function () {
      // stop impersonating whale
      await hre.network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [USDC_WHALE],
      })
      await hre.network.provider.request({
        method: 'hardhat_stopImpersonatingAccount',
        params: [WAVAX_WHALE],
      })
    })

    it('should repay USDC and seize AVAX', async () => {
      const accounts = await hre.ethers.getSigners()
      const BORROWER = accounts[0].address
      await network.provider.send('hardhat_setBalance', [BORROWER, '0x6750000000000000000000000'])

      // fund borrower
      const supplyAmount = new BN(10).pow(new BN(WAVAX_DECIMALS)).muln(50)
      await wavaxToken.transfer(BORROWER, supplyAmount, { from: WAVAX_WHALE })

      // mint jAVAX
      await wavaxToken.approve(jAVAXToken.address, supplyAmount, { from: BORROWER })
      await jAVAXToken.mint(supplyAmount, { from: BORROWER })

      // enter market
      const joetroller = await Joetroller.at(JOETROLLER)
      await joetroller.enterMarkets([jAVAXToken.address], { from: BORROWER })

      // borrow
      const priceOracle = await PriceOracle.at(PRICE_ORACLE)
      const avaxPrice = await priceOracle.getUnderlyingPrice(jAVAX)
      const avaxPriceUSD = avaxPrice / pow(10, WAVAX_DECIMALS)
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

      await testTraderJoeFlashLoan.liquidate(
        BORROWER,
        jUSDCtoken.address,
        Math.trunc(borrowAmount / 2),
        jAVAXToken.address
      )

      const expectedProfitInUSDC = Math.trunc(borrowAmount / 2) * 0.065
      expect(Number(await usdcToken.balanceOf(testTraderJoeFlashLoan.address))).to.be.at.least(expectedProfitInUSDC)
    })
  })
})
