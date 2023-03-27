// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMappingToken {
    function initialize(
        string memory,
        string memory,
        uint256
    ) external;

    function mint(address, uint256) external;

    function mintByLock(address, uint256) external;

    function burnFrom(address, uint256) external;

    function setPair(address) external;

    function setPool(address) external;

    function transferOwnership(address) external;

    function approve(address, uint256) external;

    function owner() external view returns (address);

    function uniswapPool() external view returns (address);

    function auctionPool() external view returns (address);
}
