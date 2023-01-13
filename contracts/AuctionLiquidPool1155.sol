// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./BaseAuctionLiquidPool.sol";
import "./libraries/DecimalMath.sol";

contract AuctionLiquidPool1155 is BaseAuctionLiquidPool, ERC1155HolderUpgradeable {
    using DecimalMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    EnumerableSetUpgradeable.UintSet private tokenIds;
    EnumerableSetUpgradeable.UintSet private freeTokenIds;
    EnumerableSetUpgradeable.Bytes32Set private pendingRequests;

    modifier onlyExistingId(uint256 tokenId) {
        require(tokenIds.contains(tokenId), "Pool: NON_EXISTENCE_NFT");
        _;
    }

    function initialize(
        address coordinator,
        address link,
        address token,
        address mToken,
        PoolParams memory params
    ) public initializer {
        __BaseAuctionLiquidPool_init(coordinator, link, token, mToken, params);
        __ERC1155Holder_init();

        for (uint256 i; i < params.tokenIds.length; i += 1) {
            tokenIds.add(params.tokenIds[i]);
            freeTokenIds.add(params.tokenIds[i]);
        }
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function redeem(uint256 count) external override returns (bytes32[] memory requestIds) {
        require(block.timestamp < createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(LINK.balanceOf(address(this)) >= fee * count, "Pool: INSUFFICIENT_LINK");
        require(freeTokenIds.length() >= count, "Pool: NO_FREE_NFTS");

        requestIds = new bytes32[](count);
        for (uint256 i; i < count; i += 1) {
            requestIds[i] = requestRandomness(keyHash, fee);
            redeemers[requestIds[i]] = msg.sender;
            pendingRequests.add(requestIds[i]);
        }
        emit RedeemRequested(msg.sender, requestIds);
    }

    /**
     * @notice user can swap random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function swap(uint256 tokenId) external override returns (bytes32 requestId) {
        require(IERC1155(nft).balanceOf(msg.sender, tokenId) > 0, "Pool: NOT_OWNER");
        require(block.timestamp < createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(LINK.balanceOf(address(this)) >= fee, "Pool: INSUFFICIENT_LINK");
        require(freeTokenIds.length() > 0, "Pool: NO_FREE_NFTS");

        requestId = requestRandomness(keyHash, fee);
        swaps[requestId] = tokenId;
        swapper[requestId] = msg.sender;
        emit SwapRequested(msg.sender, tokenId, requestId);
    }

    /**
     * @notice above {redeem} function makes random number generation request
     * @param requestId above {redeem} function returns requestId per request
     * @param randomness generated random number to determine which tokenId to redeem
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        address requestor;
        uint256 tokenId = freeTokenIds.at(randomness % freeTokenIds.length());
        uint256 swapId = swaps[requestId];
        if (redeemers[requestId] != address(0)) {
            requestor = redeemers[requestId];
            delete redeemers[requestId];
            emit Redeemed(requestor, requestId, tokenId);
        } else if (swapId > 0) {
            requestor = swapper[requestId];
            IERC1155(nft).safeTransferFrom(requestor, address(this), swapId, 1, "");
            tokenIds.add(swapId);
            freeTokenIds.add(swapId);
            delete swaps[requestId];
            delete swapper[requestId];
            emit Swaped(requestor, requestId, tokenId);
        } else {
            revert("Pool: INVALID_REQUEST_ID");
        }

        tokenIds.remove(tokenId);
        freeTokenIds.remove(tokenId);
        pendingRequests.remove(requestId);
        _distributeFee(requestor);
        IERC1155(nft).safeTransferFrom(address(this), requestor, tokenId, 1, "");
    }

    /**
     * @notice start auction for tokenId
     * @dev any user can start auction for a targeted NFT
     * @param tokenId targeted token Id
     */
    function startAuction(uint256 tokenId) external override onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        if (auction.startedAt > 0) {
            require(block.timestamp > auction.startedAt + duration, "Pool: STILL_ACTIVE");
            delete auctions[tokenId];

            if (auction.bidAmount > 0) {
                tokenIds.remove(tokenId);
                IMappingToken(mappingToken).burnFrom(address(this), ratio);
                IERC1155(nft).safeTransferFrom(address(this), auction.winner, tokenId, 1, "");
            } else freeTokenIds.add(tokenId);
            payable(owner()).transfer(auction.bidAmount);
        }
        auctions[tokenId].startedAt = block.timestamp;
        freeTokenIds.remove(tokenId);
    }

    /**
     * @notice end auction for tokenId
     * @dev only pool owner can end the auction
     * - transfer NFT to auction winner,
     * - burn staked maNFT
     * - transfer ether to pool owner as premium
     * @param tokenId targeted token Id
     */
    function endAuction(uint256 tokenId) external override onlyOwner onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        require(
            auctions[tokenId].startedAt > 0 &&
                block.timestamp > auctions[tokenId].startedAt + duration,
            "Pool: STILL_ACTIVE"
        );

        delete auctions[tokenId];
        if (auction.bidAmount > 0) {
            tokenIds.remove(tokenId);
            IMappingToken(mappingToken).burnFrom(address(this), ratio);
            IERC1155(nft).safeTransferFrom(address(this), auction.winner, tokenId, 1, "");
        } else freeTokenIds.add(tokenId);
        payable(owner()).transfer(auction.bidAmount);
    }

    /**
     * @notice cancel auction for tokenId
     * @dev only pool owner can end the auction
     * - return bid amounts to bidder,
     * - lock NFT back to contract
     * @param tokenId targeted token Id
     */
    function cancelAuction(uint256 tokenId) external override onlyOwner onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        delete auctions[tokenId];
        freeTokenIds.add(tokenId);
        if (auction.bidAmount > 0) {
            payable(auction.winner).transfer(auction.bidAmount);
            IERC20(mappingToken).safeTransfer(auction.winner, ratio);
        }
    }

    /**
     * @notice bid to the auction for tokenId
     * @dev any user can bid with ratio amount of maNFT and customized amount of ether
     * bid flow is like this
     * first user comes with ratio amount of maNFT and more than 0.1 amount of ether
     * for next bids, ether amount should be higher than the amount determined by price curve and delta,
     * maNFT amount would be always the same - ratio.
     * @param tokenId targeted token Id
     */
    function bid(uint256 tokenId) external payable override {
        Auction storage auction = auctions[tokenId];
        require(block.timestamp < auction.startedAt + duration, "Pool: EXPIRED");
        require(msg.value >= startPrice, "Pool: TOO_LOW_BID");

        if (auction.bidAmount == 0) {
            IERC20(mappingToken).safeTransferFrom(msg.sender, address(this), ratio);
            auction.bidAmount = msg.value;
            // if (msg.value > startPrice) payable(msg.sender).transfer(msg.value - startPrice);
        } else {
            uint256 nextBidAmount = isLinear
                ? auction.bidAmount + delta
                : auction.bidAmount + auction.bidAmount.decimalMul(delta);
            require(msg.value >= nextBidAmount, "Pool: INSUFFICIENT_BID");
            if (msg.value > nextBidAmount) payable(msg.sender).transfer(msg.value - nextBidAmount);
            auction.bidAmount = nextBidAmount;

            IERC20(mappingToken).transfer(auction.winner, ratio);
            IERC20(mappingToken).safeTransferFrom(msg.sender, address(this), ratio);
        }
        auction.winner = msg.sender;
    }

    function getTokenIds() external view override returns (uint256[] memory tokenIds_) {
        tokenIds_ = new uint256[](tokenIds.length());
        unchecked {
            for (uint256 i; i < tokenIds_.length; i += 1) tokenIds_[i] = tokenIds.at(i);
        }
    }

    function recoverNFTs() external override onlyOwner {
        for (uint256 i; i < tokenIds.length(); i += 1)
            IERC1155(nft).safeTransferFrom(
                address(this),
                owner(),
                tokenIds.at(i),
                IERC1155(nft).balanceOf(address(this), tokenIds.at(i)),
                ""
            );
    }
}
