// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./BaseAuctionLiquidPool.sol";
import "./libraries/DecimalMath.sol";

contract AuctionLiquidPool721 is BaseAuctionLiquidPool, ERC721HolderUpgradeable {
    using DecimalMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    EnumerableSetUpgradeable.UintSet private tokenIds;
    EnumerableSetUpgradeable.UintSet private freeTokenIds;

    function initialize(
        address coordinator,
        address token,
        address mToken,
        PoolParams memory params
    ) public initializer {
        __BaseAuctionLiquidPool_init(coordinator, token, mToken, params);
        __ERC721Holder_init();

        for (uint256 i; i < params.tokenIds.length; ++i) {
            tokenIds.add(params.tokenIds[i]);
            freeTokenIds.add(params.tokenIds[i]);
        }
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request random number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomWords}
     */
    function redeem(uint32 count) external override returns (uint256 requestId) {
        require(block.timestamp < createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(freeTokenIds.length() >= count, "Pool: NO_FREE_NFTS");

        requestId = requestRandomWords(count);
        redeemers[requestId] = msg.sender;
        emit RedeemRequested(msg.sender, requestId);
    }

    /**
     * @notice user can swap random NFT by paying ratio amount of maNFT
     * @dev this will request random number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomWords}
     */
    function swap(uint256 tokenId) external override returns (uint256 requestId) {
        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "Pool: NOT_OWNER");
        require(block.timestamp < createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(freeTokenIds.length() > 0, "Pool: NO_FREE_NFTS");

        requestId = requestRandomWords(1);
        swaps[requestId] = tokenId;
        emit SwapRequested(msg.sender, tokenId, requestId);
    }

    /**
     * @notice above {redeem} function makes random number generation request
     * @param requestId above {redeem} function returns requestId per request
     * @param randomWords generated random number to determine which tokenId to redeem
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        if (freeTokenIds.length() == 0) return;

        uint256[] memory tokenIds_ = new uint256[](randomWords.length);
        address requestor = redeemers[requestId];
        if (swaps[requestId] > 0) {
            tokenIds_[0] = freeTokenIds.at(randomWords[0] % freeTokenIds.length());
            uint256 swapId = swaps[requestId];
            requestor = IERC721(nft).ownerOf(swapId);
            tokenIds.add(swapId);
            freeTokenIds.add(swapId);
            tokenIds.remove(tokenIds_[0]);
            freeTokenIds.remove(tokenIds_[0]);
            delete swaps[requestId];
            IERC721(nft).safeTransferFrom(requestor, address(this), swapId);
            IERC721(nft).safeTransferFrom(address(this), requestor, tokenIds_[0]);
            emit Swaped(requestor, requestId, tokenIds_[0]);
        } else if (requestor != address(0)) {
            for (uint256 i; i < randomWords.length; ++i) {
                tokenIds_[i] = freeTokenIds.at(randomWords[i] % freeTokenIds.length());
                tokenIds.remove(tokenIds_[i]);
                freeTokenIds.remove(tokenIds_[i]);
                IERC721(nft).safeTransferFrom(address(this), requestor, tokenIds_[i]);
            }
            emit Redeemed(requestor, requestId, tokenIds_);
        } else {
            revert("Pool: INVALID_REQUEST_ID");
        }
        _distributeFee(requestor, randomWords.length);
    }

    /**
     * @notice start auction for tokenId
     * @dev any user can start auction for a targeted NFT
     * @param tokenId targeted token Id
     */
    function startAuction(uint256 tokenId) external override {
        require(freeTokenIds.contains(tokenId), "Pool: NFT_IN_AUCTION");
        IERC20(mappingToken).safeTransferFrom(msg.sender, address(this), ratio);
        IERC20(dexToken).safeTransferFrom(msg.sender, address(this), startPrice);
        auctions[tokenId] = Auction(msg.sender, startPrice, block.timestamp);
        freeTokenIds.remove(tokenId);
        emit AuctionStarted(tokenId, msg.sender);
    }

    /**
     * @notice end auction for tokenId
     * @dev only pool owner can end the auction
     * - transfer NFT to auction winner,
     * - burn staked maNFT
     * - transfer ether to pool owner as premium
     * @param tokenId targeted token Id
     */
    function endAuction(uint256 tokenId) external override {
        require(
            tokenIds.contains(tokenId) && !freeTokenIds.contains(tokenId),
            "Pool: NO_AUCTION_FOR_NFT"
        );
        Auction memory auction = auctions[tokenId];
        require(auction.startedAt + duration < block.timestamp, "Pool: STILL_ACTIVE");
        require(auction.winner == msg.sender, "Pool: NOT_WINNER");

        delete auctions[tokenId];
        tokenIds.remove(tokenId);
        IMappingToken(mappingToken).burnFrom(address(this), ratio);
        IERC721(nft).safeTransferFrom(address(this), auction.winner, tokenId);
        emit AuctionEnded(tokenId, msg.sender);
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
    function bid(uint256 tokenId) external override {
        Auction storage auction = auctions[tokenId];
        require(block.timestamp < auction.startedAt + duration, "Pool: EXPIRED");

        uint256 nextBidAmount = isLinear
            ? auction.bidAmount + delta
            : auction.bidAmount + auction.bidAmount.decimalMul(delta);
        IERC20(mappingToken).safeTransfer(auction.winner, ratio);
        IERC20(mappingToken).safeTransferFrom(msg.sender, address(this), ratio);
        IERC20(dexToken).safeTransfer(auction.winner, auction.bidAmount);
        IERC20(dexToken).safeTransferFrom(msg.sender, address(this), nextBidAmount);
        auction.bidAmount = nextBidAmount;
        auction.winner = msg.sender;
        emit BidPlaced(tokenId, msg.sender, nextBidAmount);
    }

    function recoverNFTs() external override onlyOwner {
        for (uint256 i; i < tokenIds.length(); ++i)
            IERC721(nft).safeTransferFrom(address(this), owner(), tokenIds.at(i));
    }

    function lockNFTs(uint256[] calldata tokenIds_) external override onlyOwner {
        for (uint256 i; i < tokenIds_.length; ++i) {
            require(!tokenIds.contains(tokenIds_[i]), "Pool: NFT_ALREADY_LOCKED");
            IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds_[i]);
        }
        emit NFTsLocked(tokenIds_);
    }

    function getTokenIds() external view override returns (uint256[] memory tokenIds_) {
        tokenIds_ = new uint256[](tokenIds.length());
        unchecked {
            for (uint256 i; i < tokenIds_.length; ++i) tokenIds_[i] = tokenIds.at(i);
        }
    }

    function getFreeTokenIds() external view override returns (uint256[] memory tokenIds_) {
        tokenIds_ = new uint256[](freeTokenIds.length());
        unchecked {
            for (uint256 i; i < tokenIds_.length; ++i) tokenIds_[i] = freeTokenIds.at(i);
        }
    }
}
