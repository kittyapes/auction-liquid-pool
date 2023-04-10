// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IBaseAuctionLiquidPool {
    enum FeeType {
        PROJECT,
        AMM_POOL,
        NFT_HOLDERS,
        LP
    }

    struct PoolParams {
        // name of the collection for mapping token
        string name;
        // pool avatar ipfs url
        string logo;
        // owner of the pool
        address owner;
        // nft contract address
        address nft;
        // nft locking period
        uint64 lockPeriod;
        // auction period
        uint64 duration;
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
        uint16 randomFee;
        uint16 tradingFee;
        uint256 startPrice;
        FeeType[] feeTypes;
        uint16[] feeValues;
    }
}
