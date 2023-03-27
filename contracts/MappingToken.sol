// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MappingToken is OwnableUpgradeable, ERC20Upgradeable {
    address public uniswapPool;
    address public auctionPool;

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 amount
    ) public initializer {
        __Ownable_init();
        __ERC20_init(name_, symbol_);
        _mint(msg.sender, amount);
    }

    function mintByLock(address to, uint256 amount) external {
        require(msg.sender == auctionPool, "MappingToken: NOT_FROM_POOL");
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        if (allowance(from, msg.sender) >= amount) _burn(from, amount);
    }

    function setPair(address pair) external onlyOwner {
        uniswapPool = pair;
    }

    function setPool(address pool) external onlyOwner {
        auctionPool = pool;
    }
}
