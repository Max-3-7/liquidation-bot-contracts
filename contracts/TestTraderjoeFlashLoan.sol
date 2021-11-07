// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/traderjoe/ERC3156FlashBorrowerInterface.sol";
import "./interfaces/traderjoe/ERC3156FlashLenderInterface.sol";
import "./interfaces/traderjoe/JCollateralCapErc20.sol";
import "./interfaces/traderjoe/JTokenInterface.sol";
import "./interfaces/traderjoe/Joetroller.sol";
import "./Liquidator.sol";

import "hardhat/console.sol";

contract TestTraderJoeFlashLoan is ERC3156FlashBorrowerInterface {
    using SafeMath for uint256;

    Joetroller public joetroller =
        Joetroller(0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC);

    Liquidator public liquidator;

    address public owner;

    constructor(Liquidator _liquidator) {
        liquidator = _liquidator;
        owner = msg.sender;
    }

    function liquidate(
        address borrower,
        address repayAsset,
        uint256 repayAmount,
        address collateralAsset
    ) external {
        require(msg.sender == owner, "not owner");

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

        (uint256 error, uint256 liquidity, uint256 shortfall) = joetroller
            .getAccountLiquidity(borrower);
        console.log("Error", error);
        console.log("Liquidity", liquidity);
        console.log("Shortfall", shortfall);

        ERC3156FlashLenderInterface(repayAsset).flashLoan(
            this,
            repayAsset,
            repayAmount,
            data
        );

        // NOTE: CODE BELOW WORKS

        // IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
        // console.log("USDC BALANCE", usdc.balanceOf(address(this)));
        // usdc.approve(repayAsset, repayAmount);

        // console.log(
        //     "Seized tokens before",
        //     JCollateralCapErc20(collateralAsset).balanceOf(address(this))
        // );

        // require(
        //     JCollateralCapErc20(repayAsset).liquidateBorrow(
        //         borrower,
        //         repayAmount,
        //         JTokenInterface(collateralAsset)
        //     ) == 0,
        //     "liquidation failed"
        // );

        // console.log(
        //     "Seized tokens",
        //     JCollateralCapErc20(collateralAsset).balanceOf(address(this))
        // );

        // // redeem jAsset
        // uint redeemAmount = JCollateralCapErc20(collateralAsset).balanceOf(address(this));
        // JCollateralCapErc20(collateralAsset).redeemUnderlying(redeemAmount);
        // console.log("AVAX BALANCE", IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7).balanceOf(address(this)));
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
        IERC20(token).approve(msg.sender, amountOwing);

        // TODO: liquidate, swap collateral for stable (or avax?), have enough fund to cover fee

        // liquidate borrower
        (
            address borrower,
            address repayAsset,
            address collateralAsset,
            uint256 repayAmount
        ) = abi.decode(data, (address, address, address, uint256));

        console.log("Initiator", initiator);
        console.log("Repay asset", repayAsset);

        // IERC20(token).approve(repayAsset, repayAmount);

        (uint256 error, uint256 cTokenCollateralAmount) = joetroller
            .liquidateCalculateSeizeTokens(repayAsset, collateralAsset, amount);

        console.log("Error liquidateCalculateSeizeTokens", error);
        console.log("liquidateCalculateSeizeTokens", cTokenCollateralAmount);

        console.log("Repay amount", repayAmount);
        console.log("Collateral asset ", collateralAsset);
        // executeLiquidate(borrower, repayAsset, repayAmount, collateralAsset);

        IERC20(token).approve(initiator, amount);
        require(
            JCollateralCapErc20(initiator).liquidateBorrow(
                borrower,
                amount,
                JTokenInterface(collateralAsset)
            ) == 0,
            "liquidation failed"
        );

        console.log(
            "Seized tokens",
            JCollateralCapErc20(collateralAsset).balanceOf(address(this))
        );
        // IERC20(repayAsset).approve(spender, amount);
        // console.log("Balance liquidator token before transfer", IERC20(token).balanceOf(address(liquidator)));
        // IERC20(token).transfer(address(liquidator), amount);
        // console.log("Balance liquidator token after transfer", IERC20(token).balanceOf(address(liquidator)));
        // liquidator.liquidate(borrower, repayAsset, repayAmount, collateralAsset);

        // redeem jAsset
        // uint redeemAmount = JCollateralCapErc20(token).balanceOf(address(this));
        // JCollateralCapErc20(collateralAsset).redeemUnderlying(redeemAmount);

        // swap seized assets for stable coins

        return keccak256("ERC3156FlashBorrowerInterface.onFlashLoan");
    }

    // function executeLiquidate(address borrower, address repayAsset, uint repayAmount, address collateralAsset) private {
    //     require(
    //         JCollateralCapErc20(repayAsset).liquidateBorrow(
    //             borrower,
    //             repayAmount,
    //             JTokenInterface(collateralAsset)
    //         ) == 0,
    //         "liquidation failed"
    //     );
    // }
}
