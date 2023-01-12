// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBaseAuctionLiquidPool {
    struct PoolParams {
        // name of the collection for mapping token
        string name;
        // owner of the pool
        address owner;
        // nft contract address
        address nft;
        // nft locking period
        uint256 lockPeriod;
        // auction period
        uint256 duration;
        // target nfts to lock
        uint256[] tokenIds;
        // price curve type - true: linear, false: exponential
        bool isLinear;
        /**
        if linear, price difference
        if exponential, price difference in percentage
     */
        uint256 delta;
        // maNFT ratio, e.g. 1:1, 1:100
        uint256 ratio;
        uint256 randomFee;
        uint256 tradingFee;
        uint256 startPrice;
    }
}
