// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DexToken is Ownable, ERC20("DEX Token", "DEXT") {
    constructor() {
        _mint(msg.sender, 1e24);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        if (allowance(from, msg.sender) >= amount) _burn(from, amount);
    }
}
