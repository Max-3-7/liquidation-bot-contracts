// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8;
import "./ERC3156FlashBorrowerInterface.sol";

interface ERC3156FlashLenderInterface {
    function flashLoan(
        ERC3156FlashBorrowerInterface receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}
