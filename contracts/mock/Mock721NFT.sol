//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Mock721NFT is ERC721("Mock NFT", "MOCK") {
    uint256 private lastTokenId;

    function mint(uint256 amount) external {
        for (uint256 i; i < amount; i += 1) _safeMint(msg.sender, lastTokenId++);
    }
}
