pragma solidity ^0.8;

import "./JToken.sol";
import "./PriceOracle.sol";

interface Joetroller {
    function _setCollateralFactor(
        JToken jToken,
        uint256 newCollateralFactorMantissa
    ) external returns (uint256);

    function _setPriceOracle(PriceOracle newOracle) external returns (uint256);

    function enterMarkets(address[] memory jTokens)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function liquidateCalculateSeizeTokens(
        address jTokenBorrowed,
        address jTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256);
}
