// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/traderjoe/ERC3156FlashBorrowerInterface.sol";
import "./interfaces/traderjoe/JCollateralCapErc20.sol";
import "./interfaces/traderjoe/JTokenInterface.sol";
import "./interfaces/traderjoe/Joetroller.sol";
import "./interfaces/traderjoe/JoeRouter02.sol";

import "hardhat/console.sol";

contract TestTraderJoeFlashLoan is ERC3156FlashBorrowerInterface {
    using SafeMath for uint256;

    address private constant JOE_ROUTER =
        0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address private constant JOETROLLER =
        0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC;
    address private constant PRICE_ORACLE =
        0xe34309613B061545d42c4160ec4d64240b114482;

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant JAVAX = 0xC22F01ddc8010Ee05574028528614634684EC29e;
    address private constant USDC = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    address private constant JUSDC = 0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC;
    address private constant JUSDT = 0x8b650e26404AC6837539ca96812f0123601E4448;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function liquidate(
        address borrower,
        address repayAsset,
        uint256 repayAmount, // TODO: I think the smart contract should determine how much to borrow based on joetroller close factor
        address collateralAsset
    ) external {
        require(msg.sender == owner, "not owner");

        console.log("Repay asset", repayAsset);
        console.log("Repay amount", repayAmount);

        bytes memory data = abi.encode(
            borrower,
            repayAsset,
            collateralAsset,
            repayAmount
        );

        console.log(
            "Borrow balance: ",
            JCollateralCapErc20(repayAsset).borrowBalanceCurrent(borrower)
        );
        console.log(
            "Collateral balance: ",
            JCollateralCapErc20(collateralAsset).balanceOfUnderlying(borrower)
        );

        (uint256 error, uint256 liquidity, uint256 shortfall) = Joetroller(
            JOETROLLER
        ).getAccountLiquidity(borrower);
        console.log("Error", error);
        console.log("Liquidity", liquidity);
        console.log("Shortfall", shortfall);

        // NOTE : borrowed, seized and repayed assets has to be different because of nonReentrant functions
        // TODO: handle all possible cases
        address borrowAsset;
        uint256 borrowAmount;
        if (repayAsset == JAVAX) {
            borrowAsset = JUSDC;
            borrowAmount =
                (PriceOracle(PRICE_ORACLE).getUnderlyingPrice(
                    JToken(repayAsset)
                ) * repayAmount) /
                10**18 /
                10**12; // TODO: DECIMALS ?
        } else if (collateralAsset == JAVAX) {
            borrowAsset = JUSDT;
            borrowAmount =
                (PriceOracle(PRICE_ORACLE).getUnderlyingPrice(
                    JToken(repayAsset)
                ) * repayAmount) /
                10**18 /
                10**12; // TODO: DECIMALS ?
        } else {
            borrowAsset = JAVAX;
            borrowAmount =
                (PriceOracle(PRICE_ORACLE).getUnderlyingPrice(
                    JToken(repayAsset)
                ) * repayAmount) /
                PriceOracle(PRICE_ORACLE).getUnderlyingPrice(JToken(JAVAX)); // TODO: DECIMALS ?
        }

        console.log("BORROW ASSET", borrowAsset);
        console.log("BORROW AMOUNT", borrowAmount);

        JCollateralCapErc20(borrowAsset).flashLoan(
            this,
            address(this),
            borrowAmount,
            data
        );
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        console.log("Borrowed", amount);
        console.log("Fee", fee);

        console.log("Token", token);

        uint256 amountOwing = amount.add(fee);
        console.log("Amount owing", amountOwing);

        console.log("BALANCE CHECK", IERC20(token).balanceOf(address(this)));
        IERC20(token).approve(msg.sender, amountOwing);

        (
            address borrower,
            address repayAsset,
            address collateralAsset,
            uint256 repayAmount
        ) = abi.decode(data, (address, address, address, uint256));

        console.log("Initiator", initiator);
        console.log("Repay asset", repayAsset);

        // 1. swap token for repayAsset underlying
        address repayAssetUnderlying = JCollateralCapErc20(repayAsset)
            .underlying();
        console.log("repayAssetUnderlying", repayAssetUnderlying);
        swap(token, repayAssetUnderlying, amount, 1, address(this)); // TODO: not 1 but getAmountOutMin ?
        console.log(
            "Repay asset amount",
            JToken(repayAssetUnderlying).balanceOf(address(this))
        );

        console.log(
            "Seized tokens before liquidate borrow",
            JCollateralCapErc20(collateralAsset).balanceOf(address(this))
        );

        // 2. liquidateBorrow
        IERC20(repayAssetUnderlying).approve(repayAsset, amount);
        require(
            JCollateralCapErc20(repayAsset).liquidateBorrow(
                borrower,
                JToken(repayAssetUnderlying).balanceOf(address(this)),
                JTokenInterface(collateralAsset)
            ) == 0,
            "liquidation failed"
        );

        swapSeizedTokens(collateralAsset, token, amountOwing);

        return keccak256("ERC3156FlashBorrowerInterface.onFlashLoan");
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) private {
        IERC20(tokenIn).approve(JOE_ROUTER, amountIn);

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

        JoeRouter02(JOE_ROUTER).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            block.timestamp
        );
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
        uint256[] memory amountOutMins = JoeRouter02(JOE_ROUTER).getAmountsOut(
            amountIn,
            path
        );

        return amountOutMins[path.length - 1];
    }

    function swapSeizedTokens(
        address seizedAsset,
        address token,
        uint256 amountOwing
    ) private {
        // redeem jAsset
        uint256 underlyingSeizedTokens = JCollateralCapErc20(seizedAsset)
            .balanceOfUnderlying(address(this));
        console.log("Seized tokens", underlyingSeizedTokens);
        JCollateralCapErc20(seizedAsset).redeemUnderlying(
            underlyingSeizedTokens
        );

        // swap seized tokens for borrowed asset
        address seizedUnderlyingAsset = JCollateralCapErc20(seizedAsset)
            .underlying();
        console.log("Seized tokens underlying address", seizedUnderlyingAsset);
        uint256 seizedUnderlyingTokens = IERC20(seizedUnderlyingAsset)
            .balanceOf(address(this));
        console.log("Seized tokens underlying", seizedUnderlyingTokens);
        swap(
            seizedUnderlyingAsset,
            token,
            seizedUnderlyingTokens,
            getAmountOutMin(
                seizedUnderlyingAsset,
                token,
                seizedUnderlyingTokens
            ),
            address(this)
        );

        // swap profits to USDC if needed
        if (seizedAsset != JUSDC) {
            uint256 tokenAmount = IERC20(token).balanceOf(address(this));
            uint256 profitTokens = tokenAmount - amountOwing;
            swap(token, USDC, profitTokens, 1, address(this));
            console.log(
                "Profit in USDC after repaying amountOwing",
                profitTokens
            );
        } else {
            console.log(
                "Profit in USDC after repaying amountOwing",
                IERC20(USDC).balanceOf(address(this)) - amountOwing
            );
        }
    }
}
