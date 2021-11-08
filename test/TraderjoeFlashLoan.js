const { expect } = require('chai');
const { pow } = require("./util.js");
const { ethers, artifacts } = require('hardhat');
const { BigNumber } = require('ethers');
const { time } = require("@openzeppelin/test-helpers")
const Web3 = require('web3');
const { getJsonWalletAddress } = require('ethers/lib/utils');
// const { time } = require('console');
const BN = require("bn.js");
// const { BigNumber } = require('@ethersproject/providers/node_modules/@ethersproject/bignumber');
const IERC20 = artifacts.require("IERC20");
const JCollateralCapErc20 = artifacts.require("JCollateralCapErc20");
const Joetroller = artifacts.require("Joetroller");
const MockContract = artifacts.require("./MockContract.sol");
const PriceOracle = artifacts.require("PriceOracle");
const JToken = artifacts.require("JToken");

describe('TraderjoeFlashLoan', function () {
  const USDC_WHALE = "0x2d1944bD960CDE5d8b14E5f8093d9E017f4Ce5A8"
  const WAVAX_WHALE = "0xda6ad74619e62503C4cbefbE02aE05c8F4314591"

  const USDC = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
  const USDC_DECIMALS = 6

  const jUSDC = "0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC"
  const jUSDC_DECIMALS = 8

  const jAVAX = "0xC22F01ddc8010Ee05574028528614634684EC29e"
  const jAVAX_DECIMALS = 8

  const WAVAX = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
  const WAVAX_DECIMALS = 18

  describe("testFlashLoan", function () {
    let TestTraderJoeFlashLoan
    let testTraderJoeFlashLoan

    let Liquidator
    let liquidator

    let jUSDCtoken
    let usdcToken
    let jAVAXToken
    let wavaxToken

    before(async function () {
      TestTraderJoeFlashLoan = await ethers.getContractFactory("TestTraderJoeFlashLoan")
      Liquidator = await ethers.getContractFactory("Liquidator")
    });

    beforeEach(async function () {
      liquidator = await Liquidator.deploy()
      await liquidator.deployed()

      testTraderJoeFlashLoan = await TestTraderJoeFlashLoan.deploy(liquidator.address)
      await testTraderJoeFlashLoan.deployed()

      jUSDCtoken = await JCollateralCapErc20.at(jUSDC)
      usdcToken = await IERC20.at(USDC)
      jAVAXToken = await JCollateralCapErc20.at(jAVAX)
      wavaxToken = await IERC20.at(WAVAX)

      // impersonate whale
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [USDC_WHALE],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [WAVAX_WHALE],
      });
      // set balance to cover gas 
      await network.provider.send("hardhat_setBalance", [
        USDC_WHALE,
        "0x6750000000000000000000000",
      ]);
      await network.provider.send("hardhat_setBalance", [
        WAVAX_WHALE,
        "0x6750000000000000000000000",
      ]);
    });

    afterEach(async function () {
      // stop impersonating whale
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [USDC_WHALE],
      });
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [WAVAX_WHALE],
      });
    })

    it("should liquidate", async () => {
      const accounts = await hre.ethers.getSigners();
      const BORROWER = accounts[0].address
      await network.provider.send("hardhat_setBalance", [
        BORROWER,
        "0x6750000000000000000000000",
      ]);

      // fund borrower
      // const supplyAmount = 1000 * pow(10, jUSDC_DECIMALS)
      // await usdcToken.transfer(BORROWER, supplyAmount, { from: USDC_WHALE })
      const supplyAmount = new BN(10).pow(new BN(WAVAX_DECIMALS)).muln(50)
      await wavaxToken.transfer(BORROWER, supplyAmount, { from: WAVAX_WHALE })

      // mint jUSDC
      // await usdcToken.approve(jUSDCtoken.address, supplyAmount, { from: BORROWER })
      // await jUSDCtoken.mint(supplyAmount, { from: BORROWER })

      // mint jAVAX 
      await wavaxToken.approve(jAVAXToken.address, supplyAmount, { from: BORROWER })
      await jAVAXToken.mint(supplyAmount, { from: BORROWER })


      // borrow USDC
      // const borrowAmount = supplyAmount * 0.8
      // await jUSDCtoken.borrow(borrowAmount, { from: BORROWER })

      // enter market
      const joetroller = await Joetroller.at("0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC")
      await joetroller.enterMarkets([jAVAXToken.address], { from: BORROWER })

      // borrow 
      const priceOracle = await PriceOracle.at("0xe34309613B061545d42c4160ec4d64240b114482")
      const avaxPrice = await priceOracle.getUnderlyingPrice(jAVAX)
      const avaxPriceUSD = avaxPrice / pow(10, WAVAX_DECIMALS)//.div(new BN(10).pow(new BN(WAVAX_DECIMALS)))
      // const maxBorrowUSD = s * 0.8
      console.log("Avax price", avaxPriceUSD)
      const supplyValueUSD = avaxPriceUSD * supplyAmount / pow(10, WAVAX_DECIMALS)//avaxPrice.mul(supplyAmount).div(new BN(10).pow(new BN(WAVAX_DECIMALS))).div(new BN(10).pow(new BN(WAVAX_DECIMALS)))//(supplyAmount * avaxPriceUSD) / pow(10, WAVAX_DECIMALS)
      console.log("Supply value USD", supplyValueUSD)
      //(maxBorrowUSD / avaxPriceUSD) * pow(10, jAVAX_DECIMALS)
      const borrowAmount = supplyValueUSD * pow(10, USDC_DECIMALS) * 0.75 * (9999 / 10000)//supplyValueUSD.mul(new BN(pow(10, USDC_DECIMALS))).muln(75).divn(100)
      console.log("Borrow amount", borrowAmount)
      await jUSDCtoken.borrow(Math.trunc(borrowAmount), { from: BORROWER })

      // accrue interest on borrow
      const block = await web3.eth.getBlockNumber()
      await time.advanceBlockTo(block + 50000) // 50000 blocks is enough

      // liquidate & seize USDC
      // const repayAmount = borrowAmount.muln(50).divn(100)
      // console.log("Repay amount", BigInt(repayAmount))

      // await usdcToken.transfer(testTraderJoeFlashLoan.address, 10000 * pow(10, USDC_DECIMALS), { from: USDC_WHALE })
      
      await testTraderJoeFlashLoan.liquidate(BORROWER, jUSDCtoken.address, Math.trunc(borrowAmount / 2), jAVAXToken.address)


    })

    // it("should liquidate", async () => {
    //   // const BORROWER = '0x01b7b3225d875dd7a02fc895decb31d3f15c7de8'
    //   const collateralToken = jAVAXToken
    //   const closeFactor = 0.5
    //   const borrowAmount = 1400 * pow(10, USDC_DECIMALS) * closeFactor

    //   // fund account to pay fee
    //   const fundAmount = 500 * pow(10, USDC_DECIMALS)
    //   await usdcToken.transfer(testTraderJoeFlashLoan.address, fundAmount, {
    //     from: USDC_WHALE,
    //   })

    //   const accounts = await hre.ethers.getSigners()
    //   const borrower = accounts[0]

    //   // const joetroller = await Joetroller.at("0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC")
    //   // await joetroller._setPriceOracle(mock)
    //   // const ts = await joetroller._setCollateralFactor(jAVAXToken.address, ethers.utils.parseEther('0.2')).catch((err) => console.log(err))
    //   // console.log(ts)

    //   // unlock borrower account
    //   await hre.network.provider.request({
    //     method: "hardhat_impersonateAccount",
    //     params: [BORROWER],
    //   });
    //   await network.provider.send("hardhat_setBalance", [
    //     BORROWER,
    //     "0x6750000000000000000000000",
    //   ]);

    //   // borrow more assets so the account is underwater
    //   const priceOracle = await PriceOracle.at("0xe34309613B061545d42c4160ec4d64240b114482")
    //   const avaxPrice = await priceOracle.getUnderlyingPrice(jAVAXToken.address)
    //   // console.log("Avax price", new BN(ava))

    //   const jAvaxBalance = await jAVAXToken.balanceOfUnderlying(BORROWER).catch(console.error)
    //   console.log("Borrower jAVAX balance", jAvaxBalance)

    //   let bal = await usdcToken.balanceOf(BORROWER)
    //   console.log("Borrower jUSDC balance", bal.toNumber())
    //   const tx = await jUSDCtoken.borrow(500 * pow(10, USDC_DECIMALS), { from: BORROWER })
    //   // console.log(tx)
    //   bal = await usdcToken.balanceOf(BORROWER)
    //   console.log("Borrower jUSDC balance after borrow", bal.toNumber())

    //   // wait for interest to accrue
    //   const block = await web3.eth.getBlockNumber()
    //   await time.advanceBlockTo(block + 10000)

    //   // console.log(await jAVAXToken.)

    //   await testTraderJoeFlashLoan.liquidate(BORROWER, jUSDCtoken.address, borrowAmount, collateralToken.address)
    // })

    // it("fails to pay flash loan because of fees", async () => {
    //   const borrowAmount = 10000 * pow(10, USDC_DECIMALS)
    //   await expect(testTraderJoeFlashLoan.testFlashLoan(jUSDCtoken.address, borrowAmount)).to.be.revertedWith('ERC20: transfer amount exceeds balance')
    // })
  });
});

// {
//   "data": {
//     "account": {
//       "tokens": [
//         {
//           "borrowBalanceUnderlying": "0",
//           "enteredMarket": true,
//           "supplyBalanceUnderlying": "36.0999887220763675894038528",
//           "symbol": "jAVAX"
//         },
//         {
//           "borrowBalanceUnderlying": "1400.487254312351878418354183592947",
//           "enteredMarket": true,
//           "supplyBalanceUnderlying": "0",
//           "symbol": "jUSDC"
//         }
//       ]
//     }
//   }
// }

// supply avax
// borrow usdc very close to max
// wait for X blocks
// make sure account is underwater
// liquidate


// function supply(uint _amount) external {
//   tokenSupply.transferFrom(msg.sender, address(this), _amount);
//   tokenSupply.approve(address(cTokenSupply), _amount);
//   require(cTokenSupply.mint(_amount) == 0, "mint failed");
// }