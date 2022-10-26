// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./AuctionLiquidPool.sol";

struct PoolParams {
    address owner;
    address nft;
    uint256 lockPeriod;
    uint256 duration;
    uint256[] tokenIds;
    bool isLinear;
    uint256 delta;
    uint256 ratio;
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

    function createPool(
        address nft_,
        uint256 lockPeriod_,
        uint256 duration_,
        uint256[] calldata tokenIds_,
        bool isLinear_,
        uint256 delta_,
        uint256 ratio_
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
            ratio_
        );
        AuctionLiquidPool pool = AuctionLiquidPool(poolAddress);
        pool.initialize(params);
        pool.transferOwnership(msg.sender);
        pools.push(poolAddress);

        emit PoolCreated(msg.sender, poolAddress, poolTemplate);
    }

    function setPoolTemplate(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: 0x0");
        poolTemplate = poolTemplate_;
    }
}
