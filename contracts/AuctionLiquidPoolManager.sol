// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./AuctionLiquidPool.sol";

struct PoolParams {
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

contract AuctionLiquidPoolManager is Ownable {
    address public poolTemplate;
    address public token;
    address[] public pools;

    event PoolCreated(address indexed owner_, address indexed pool_, address poolTemplate_);

    constructor(address token_) {
        require(token_ != address(0), "PoolManager: TOKEN_0x0");
        token = token_;
    }

    /**
     * @notice create pool contract locking nfts
     * @dev only nft owners can call this function to lock their own nfts
     * @return poolAddress address of generated pool
     */
    function createPool(
        address nft_,
        uint256 lockPeriod_,
        uint256 duration_,
        uint256[] calldata tokenIds_,
        bool isLinear_,
        uint256 delta_,
        uint256 ratio_,
        uint256 randomFee_,
        uint256 tradingFee_,
        uint256 startPrice_
    ) external returns (address poolAddress) {
        require(poolTemplate != address(0), "PoolManager: MISSING_VAULT_TEMPLATE");
        require(tokenIds_.length > 0, "PoolManager: INFOS_MISSING");

        poolAddress = Clones.clone(poolTemplate);
        PoolParams memory params = PoolParams(
            msg.sender,
            nft_,
            lockPeriod_,
            duration_,
            tokenIds_,
            isLinear_,
            delta_,
            ratio_,
            randomFee_,
            tradingFee_,
            startPrice_
        );
        AuctionLiquidPool pool = AuctionLiquidPool(poolAddress);
        pool.initialize(params);
        pool.transferOwnership(msg.sender);
        pools.push(poolAddress);

        for (uint256 i; i < tokenIds_.length; i += 1)
            IERC721(nft_).safeTransferFrom(msg.sender, poolAddress, tokenIds_[i]);

        emit PoolCreated(msg.sender, poolAddress, poolTemplate);
    }

    /**
     * @notice set pool template
     * @dev only manager contract owner can call this function
     * @param poolTemplate_ new template address
     */
    function setPoolTemplate(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: 0x0");
        poolTemplate = poolTemplate_;
    }
}
