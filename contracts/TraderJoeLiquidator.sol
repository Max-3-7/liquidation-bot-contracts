// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './interfaces/traderjoe/ERC3156FlashBorrowerInterface.sol';
import './interfaces/traderjoe/JCollateralCapErc20.sol';
import './interfaces/traderjoe/JTokenInterface.sol';
import './interfaces/traderjoe/Joetroller.sol';
import './interfaces/traderjoe/JoeRouter02.sol';

contract TraderJoeLiquidator is ERC3156FlashBorrowerInterface {
    using SafeMath for uint256;

    address private WAVAX;
    address private JAVAX;
    address private USDC;
    address private JUSDC;
    address private JUSDT;
    address private JOETROLLER;
    address private JOEROUTER02;

    address public owner;

    constructor(
        address joetroller,
        address joeRouter02,
        address wavax,
        address usdc,
        address javax,
        address jusdc,
        address jusdt
    ) {
        owner = msg.sender;

        JOETROLLER = joetroller;
        JOEROUTER02 = joeRouter02;
        WAVAX = wavax;
        JAVAX = javax;
        JUSDC = jusdc;
        JUSDT = jusdt;
        USDC = usdc;
    }

    function withdraw(address asset) external {
        require(msg.sender == owner, 'not owner');

        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance > 0, 'not enough balance');

        IERC20(asset).approve(address(this), balance);
        IERC20(asset).transfer(owner, balance);
    }

    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall) {
        // liquidity and shortfall in USD scaled up by 1e18
        (uint256 error, uint256 _liquidity, uint256 _shortfall) = Joetroller(JOETROLLER).getAccountLiquidity(borrower);
        require(error == 0, 'error');
        return (_liquidity, _shortfall);
    }

    function liquidate(
        address borrower,
        address repayAsset,
        address collateralAsset
    ) external {
        require(msg.sender == owner, 'not owner');

        bytes memory data = abi.encode(borrower, repayAsset, collateralAsset);

        PriceOracle priceOracle = PriceOracle(Joetroller(JOETROLLER).oracle());

        uint256 borrowBalance = JCollateralCapErc20(repayAsset).borrowBalanceCurrent(borrower);
        uint256 collateralBalance = JCollateralCapErc20(collateralAsset).balanceOfUnderlying(borrower);
        uint256 collateralBalanceUSD = (collateralBalance * priceOracle.getUnderlyingPrice(JToken(collateralAsset))) /
            10**18;

        uint256 repayAmount = (borrowBalance * Joetroller(JOETROLLER).closeFactorMantissa()) / 10**18;
        uint256 repayAmountUSD = (repayAmount * priceOracle.getUnderlyingPrice(JToken(repayAsset))) / 10**18;

        // NOTE : make sure the borrower has enough collateral in a single token for the max repay amount
        if (repayAmountUSD >= collateralBalanceUSD) {
            repayAmount = ((((collateralBalanceUSD * 10**18) / Joetroller(JOETROLLER).liquidationIncentiveMantissa()) *
                10**18) / priceOracle.getUnderlyingPrice(JToken(repayAsset)));
        }

        (address borrowAsset, uint256 borrowAmount) = getBorrowAssetAndAmount(repayAsset, collateralAsset, repayAmount);
        JCollateralCapErc20(borrowAsset).flashLoan(this, address(this), borrowAmount, data);
    }

    // NOTE : borrowed/seized and borrowed/repayed assets have to be different because of nonReentrant functions
    function getBorrowAssetAndAmount(
        address repayAsset,
        address collateralAsset,
        uint256 repayAmount
    ) private view returns (address, uint256) {
        address borrowAsset;
        uint256 borrowAmount;
        PriceOracle priceOracle = PriceOracle(Joetroller(JOETROLLER).oracle());

        if (repayAsset == JAVAX || collateralAsset == JAVAX) {
            if (repayAsset != JUSDT && collateralAsset != JUSDT) {
                borrowAsset = JUSDT;
            } else {
                borrowAsset = JUSDC;
            }
            borrowAmount = (priceOracle.getUnderlyingPrice(JToken(repayAsset)) * repayAmount) / 10**18 / 10**12;
        } else {
            borrowAsset = JAVAX;
            borrowAmount =
                (priceOracle.getUnderlyingPrice(JToken(repayAsset)) * repayAmount) /
                priceOracle.getUnderlyingPrice(JToken(JAVAX));
        }

        return (borrowAsset, borrowAmount);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        uint256 amountOwing = amount.add(fee);
        IERC20(token).approve(msg.sender, amountOwing);

        (address borrower, address repayAsset, address collateralAsset) = abi.decode(data, (address, address, address));

        // 1. swap token for repayAsset underlying
        address repayAssetUnderlying = JCollateralCapErc20(repayAsset).underlying();
        uint256 repayAssetUnderlyingTokens = getAmountOutMin(token, repayAssetUnderlying, amount);
        swap(token, repayAssetUnderlying, amount, repayAssetUnderlyingTokens, address(this));

        // 2. liquidateBorrow
        uint256 maxRepayAmount = (JCollateralCapErc20(repayAsset).borrowBalanceCurrent(borrower) *
            Joetroller(JOETROLLER).closeFactorMantissa()) / 10**18;
        if (repayAssetUnderlyingTokens > maxRepayAmount) {
            repayAssetUnderlyingTokens =
                maxRepayAmount /
                Joetroller(JOETROLLER).liquidationIncentiveMantissa() /
                10**18;
        }
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
        IERC20(tokenIn).approve(JOEROUTER02, amountIn);

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

        JoeRouter02(JOEROUTER02).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp);
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
        uint256[] memory amountOutMins = JoeRouter02(JOEROUTER02).getAmountsOut(amountIn, path);

        return amountOutMins[path.length - 1];
    }

    function swapSeizedTokens(
        address seizedAsset,
        address token,
        uint256 amountOwing
    ) private {
        // redeem jAsset
        uint256 underlyingSeizedTokens = JCollateralCapErc20(seizedAsset).balanceOfUnderlying(address(this));
        JCollateralCapErc20(seizedAsset).redeemUnderlying(underlyingSeizedTokens);

        // swap seized tokens for borrowed asset
        address seizedUnderlyingAsset = JCollateralCapErc20(seizedAsset).underlying();
        uint256 seizedUnderlyingTokens = IERC20(seizedUnderlyingAsset).balanceOf(address(this));
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
        }
    }
}
