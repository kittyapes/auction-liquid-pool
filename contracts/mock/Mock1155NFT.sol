//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Mock1155NFT is ERC1155("") {
    uint256 private lastTokenId;

    function batchMint(uint256[] calldata ids, uint256[] calldata amounts) external {
        _mintBatch(msg.sender, ids, amounts, "");
    }
}
