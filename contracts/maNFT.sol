// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract maNFT is Ownable, ERC20("maNFT", "maNFT") {
    struct Snapshot {
        address from;
        address to;
        uint256 amount;
    }

    mapping(address => bool) public whitelisted;
    mapping(uint256 => Snapshot) public snapshots;
    uint256 public lastSnapshotId;

    constructor() {
        _mint(msg.sender, 1e24);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setWhitelsited(address pool, bool approved) external onlyOwner {
        require(pool != address(0), "maNFT: INVALID_ADDRESS");
        whitelisted[pool] = approved;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (whitelisted[to]) {
            snapshots[lastSnapshotId++] = Snapshot(from, to, amount);
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
