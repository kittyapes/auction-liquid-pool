// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
        address token,
        address mToken,
        PoolParams memory params
    ) public initializer {
        __BaseAuctionLiquidPool_init(token, mToken, params);
        __ERC721Holder_init();

        for (uint256 i; i < params.tokenIds.length; ++i) {
            tokenIds.add(params.tokenIds[i]);
            freeTokenIds.add(params.tokenIds[i]);
        }
    }

    /// @notice user can redeem random NFT by paying ratio amount of maNFT
    function redeem(uint32 count) external override returns (uint256[] memory tokenIds_) {
        require(block.timestamp >= createdAt + lockPeriod, "Pool: NFTS_LOCKED");
        require(count <= freeTokenIds.length(), "Pool: NO_FREE_NFTS");

        tokenIds_ = new uint256[](count);
        if (count == freeTokenIds.length()) {
            for (uint256 i; i < count; ++i) {
                tokenIds_[i] = freeTokenIds.at(i);
                tokenIds.remove(tokenIds_[i]);
                freeTokenIds.remove(tokenIds_[i]);
                IERC721(nft).safeTransferFrom(address(this), msg.sender, tokenIds_[i]);
            }
        } else {
            for (uint256 i; i < count; ++i) {
                uint256 randNo = uint256(
                    keccak256(abi.encodePacked(block.prevrandao, block.timestamp, i))
                );
                tokenIds_[i] = freeTokenIds.at(randNo % freeTokenIds.length());
                tokenIds.remove(tokenIds_[i]);
                freeTokenIds.remove(tokenIds_[i]);
                IERC721(nft).safeTransferFrom(address(this), msg.sender, tokenIds_[i]);
            }
        }
        _distributeFee(msg.sender, count);

        emit Redeemed(msg.sender, tokenIds_);
    }

    /// @notice user can swap random NFT by paying ratio amount of maNFT
    function swap(uint256 tokenId) external override returns (uint256 dstTokenId) {
        require(IERC721(nft).ownerOf(tokenId) == msg.sender, "Pool: NOT_OWNER");
        require(block.timestamp >= createdAt + lockPeriod, "Pool: NFTS_LOCKED");
        require(freeTokenIds.length() > 0, "Pool: NO_FREE_NFTS");

        uint256 randNo = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp)));
        dstTokenId = freeTokenIds.at(randNo % freeTokenIds.length());
        tokenIds.add(tokenId);
        freeTokenIds.add(tokenId);
        tokenIds.remove(dstTokenId);
        freeTokenIds.remove(dstTokenId);
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);
        IERC721(nft).safeTransferFrom(address(this), msg.sender, dstTokenId);

        emit Swaped(msg.sender, tokenId, dstTokenId);
    }

    /**
     * @notice start auction for tokenId
     * @dev any user can start auction for a targeted NFT
     * @param tokenId targeted token Id
     */
    function startAuction(uint256 tokenId) external override {
        require(block.timestamp >= createdAt + lockPeriod, "Pool: NFTS_LOCKED");
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
        uint256 len = tokenIds.length();
        for (uint256 i; i < len; ++i) {
            IERC721(nft).safeTransferFrom(address(this), owner(), tokenIds.at(0));
            tokenIds.remove(tokenIds.at(0));
        }
    }

    function lockNFTs(uint256[] calldata tokenIds_) external override {
        for (uint256 i; i < tokenIds_.length; ++i) {
            require(!tokenIds.contains(tokenIds_[i]), "Pool: NFT_ALREADY_LOCKED");
            IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds_[i]);
            tokenIds.add(tokenIds_[i]);
            freeTokenIds.add(tokenIds_[i]);
        }
        IMappingToken(mappingToken).mintByLock(msg.sender, tokenIds_.length * ratio);
        emit NFTsLocked(msg.sender, tokenIds_);
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
