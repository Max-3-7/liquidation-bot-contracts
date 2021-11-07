// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/traderjoe/ERC3156FlashBorrowerInterface.sol";
import "./interfaces/traderjoe/ERC3156FlashLenderInterface.sol";
import "./interfaces/traderjoe/JCollateralCapErc20.sol";
import "./interfaces/traderjoe/JTokenInterface.sol";
import "./interfaces/traderjoe/Joetroller.sol";

import "hardhat/console.sol";

contract Liquidator {
    using SafeMath for uint256;

    function liquidate(address borrower, address repayAsset, uint repayAmount, address collateralAsset) public {
        require(
            JCollateralCapErc20(repayAsset).liquidateBorrow(
                borrower,
                repayAmount,
                JTokenInterface(collateralAsset)
            ) == 0,
            "liquidation failed"
        );

        console.log("Seized tokens", JCollateralCapErc20(collateralAsset).balanceOf(address(this)));
    }
}