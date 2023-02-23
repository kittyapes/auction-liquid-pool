//solhint-disable
//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Mock721NFT is ERC721Enumerable {
    uint256 private lastTokenId;

    constructor() ERC721("Mock NFT", "MOCK") {}

    function mint(uint256 amount) external {
        for (uint256 i; i < amount; ++i) _safeMint(msg.sender, lastTokenId++);
    }
}
