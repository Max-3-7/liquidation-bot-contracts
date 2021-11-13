// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8;

import './JToken.sol';

interface PriceOracle {
    function getUnderlyingPrice(JToken jToken) external view returns (uint256);
}
