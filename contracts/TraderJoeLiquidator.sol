// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './interfaces/traderjoe/ERC3156FlashBorrowerInterface.sol';
import './interfaces/traderjoe/JCollateralCapErc20.sol';
import './interfaces/traderjoe/JTokenInterface.sol';
import './interfaces/traderjoe/Joetroller.sol';
import './interfaces/traderjoe/JoeRouter02.sol';

import 'hardhat/console.sol';

contract TraderJoeLiquidator is ERC3156FlashBorrowerInterface {
    using SafeMath for uint256;

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant JAVAX = 0xC22F01ddc8010Ee05574028528614634684EC29e;
    address private constant USDC = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address private constant JUSDC = 0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC;
    address private constant JUSDT = 0x8b650e26404AC6837539ca96812f0123601E4448;

    Joetroller public joetroller;
    PriceOracle public priceOracle;
    JoeRouter02 public joeRouter;

    address public owner;

    constructor() {
        owner = msg.sender;

        joetroller = Joetroller(0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC);
        priceOracle = PriceOracle(joetroller.oracle());
        joeRouter = JoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    }

    function liquidate(
        address borrower,
        address repayAsset,
        address collateralAsset
    ) external {
        require(msg.sender == owner, 'not owner');

        console.log('Repay asset', repayAsset);

        bytes memory data = abi.encode(borrower, repayAsset, collateralAsset);

        uint256 borrowBalance = JCollateralCapErc20(repayAsset).borrowBalanceCurrent(borrower);
        console.log('Borrow balance: ', borrowBalance);
        console.log('Collateral balance: ', JCollateralCapErc20(collateralAsset).balanceOfUnderlying(borrower));

        (, uint256 liquidity, uint256 shortfall) = joetroller.getAccountLiquidity(borrower);
        console.log('Liquidity', liquidity);
        console.log('Shortfall', shortfall);

        uint256 repayAmount = borrowBalance * joetroller.closeFactorMantissa();
        console.log('Repay amount', repayAmount);

        // NOTE : borrowed/seized and borrowed/repayed assets have to be different because of nonReentrant functions
        // TODO: handle all possible cases
        address borrowAsset;
        uint256 borrowAmount;
        if (repayAsset == JAVAX) {
            borrowAsset = JUSDC;
            borrowAmount =
                (priceOracle.getUnderlyingPrice(JToken(repayAsset)) * repayAmount) /
                10**18 /
                10**18 /
                10**12; // TODO: DECIMALS 18-repayAssetUnderlyingDecimals?
        } else if (collateralAsset == JAVAX) {
            borrowAsset = JUSDT;
            borrowAmount =
                (priceOracle.getUnderlyingPrice(JToken(repayAsset)) * repayAmount) /
                10**18 /
                10**18 /
                10**12; // TODO: DECIMALS ?
        } else {
            borrowAsset = JAVAX;
            borrowAmount =
                (priceOracle.getUnderlyingPrice(JToken(repayAsset)) * repayAmount) /
                priceOracle.getUnderlyingPrice(JToken(JAVAX)); // TODO: DECIMALS ?
        }

        console.log('BORROW ASSET', borrowAsset);
        console.log('BORROW AMOUNT', borrowAmount);

        JCollateralCapErc20(borrowAsset).flashLoan(this, address(this), borrowAmount, data);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        console.log('Borrowed', amount);
        console.log('Fee', fee);

        console.log('Token', token);

        uint256 amountOwing = amount.add(fee);
        console.log('Amount owing', amountOwing);

        console.log('BALANCE CHECK', IERC20(token).balanceOf(address(this)));
        IERC20(token).approve(msg.sender, amountOwing);

        (address borrower, address repayAsset, address collateralAsset) = abi.decode(data, (address, address, address));

        console.log('Initiator', initiator);
        console.log('Repay asset', repayAsset);

        // 1. swap token for repayAsset underlying
        address repayAssetUnderlying = JCollateralCapErc20(repayAsset).underlying();
        console.log('repayAssetUnderlying', repayAssetUnderlying);
        uint256 repayAssetUnderlyingTokens = getAmountOutMin(token, repayAssetUnderlying, amount);
        swap(token, repayAssetUnderlying, amount, repayAssetUnderlyingTokens, address(this));
        console.log('Repay asset amount', repayAssetUnderlyingTokens);

        console.log(
            'Seized tokens before liquidate borrow',
            JCollateralCapErc20(collateralAsset).balanceOf(address(this))
        );

        // 2. liquidateBorrow
        IERC20(repayAssetUnderlying).approve(repayAsset, repayAssetUnderlyingTokens);
        require(
            JCollateralCapErc20(repayAsset).liquidateBorrow(
                borrower,
                repayAssetUnderlyingTokens,
                JTokenInterface(collateralAsset)
            ) == 0,
            'liquidation failed'
        );

        swapSeizedTokens(collateralAsset, token, amountOwing);

        return keccak256('ERC3156FlashBorrowerInterface.onFlashLoan');
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) private {
        IERC20(tokenIn).approve(address(joeRouter), amountIn);

        address[] memory path;
        if (tokenIn == WAVAX || tokenOut == WAVAX) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WAVAX;
            path[2] = tokenOut;
        }

        joeRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
    }

    function getAmountOutMin(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256) {
        address[] memory path;
        if (tokenIn == WAVAX || tokenOut == WAVAX) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WAVAX;
            path[2] = tokenOut;
        }

        // same length as path
        uint256[] memory amountOutMins = joeRouter.getAmountsOut(amountIn, path);

        return amountOutMins[path.length - 1];
    }

    function swapSeizedTokens(
        address seizedAsset,
        address token,
        uint256 amountOwing
    ) private {
        // redeem jAsset
        uint256 underlyingSeizedTokens = JCollateralCapErc20(seizedAsset).balanceOfUnderlying(address(this));
        console.log('Seized tokens', underlyingSeizedTokens);
        JCollateralCapErc20(seizedAsset).redeemUnderlying(underlyingSeizedTokens);

        // swap seized tokens for borrowed asset
        address seizedUnderlyingAsset = JCollateralCapErc20(seizedAsset).underlying();
        console.log('Seized tokens underlying address', seizedUnderlyingAsset);
        uint256 seizedUnderlyingTokens = IERC20(seizedUnderlyingAsset).balanceOf(address(this));
        console.log('Seized tokens underlying', seizedUnderlyingTokens);
        swap(
            seizedUnderlyingAsset,
            token,
            seizedUnderlyingTokens,
            getAmountOutMin(seizedUnderlyingAsset, token, seizedUnderlyingTokens),
            address(this)
        );

        // swap profits to USDC if needed
        if (token != USDC) {
            uint256 tokenAmount = IERC20(token).balanceOf(address(this));
            uint256 profitTokens = tokenAmount - amountOwing;
            swap(token, USDC, profitTokens, 1, address(this));
            console.log('Profit in USDC after repaying amountOwing', profitTokens);
        } else {
            console.log(
                'Profit in USDC after repaying amountOwing',
                IERC20(USDC).balanceOf(address(this)) - amountOwing
            );
        }
    }
}
