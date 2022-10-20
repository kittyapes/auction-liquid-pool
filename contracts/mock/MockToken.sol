//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20("Mock", "MOCK") {
    constructor() {
        _mint(msg.sender, 1e24);
    }
}
