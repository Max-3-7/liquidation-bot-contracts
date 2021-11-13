// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import './JTokenInterface.sol';
import './ERC3156FlashBorrowerInterface.sol';

interface JCollateralCapErc20 {
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        JTokenInterface jTokenCollateral
    ) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function mint(uint256 mintAmount) external returns (uint256);

    function underlying() external view returns (address);

    function flashLoan(
        ERC3156FlashBorrowerInterface receiver,
        address initiator,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}
