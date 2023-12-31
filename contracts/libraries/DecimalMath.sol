//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library DecimalMath {
    uint256 private constant DENOMINATOR = 1000;

    function decimalMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / DENOMINATOR;
    }

    function isLessThanFull(uint256 x) internal pure returns (bool) {
        return x <= DENOMINATOR;
    }
}
