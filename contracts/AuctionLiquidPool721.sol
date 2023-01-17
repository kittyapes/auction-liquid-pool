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
import "hardhat/console.sol";

contract AuctionLiquidPool721 is BaseAuctionLiquidPool, ERC721HolderUpgradeable {
    using DecimalMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    EnumerableSetUpgradeable.UintSet private tokenIds;
    EnumerableSetUpgradeable.UintSet private freeTokenIds;

    modifier onlyExistingId(uint256 tokenId) {
        require(tokenIds.contains(tokenId), "Pool: NON_EXISTENCE_NFT");
        _;
    }

    function initialize(
        address coordinator,
        address token,
        address mToken,
        PoolParams memory params
    ) public initializer {
        __BaseAuctionLiquidPool_init(coordinator, token, mToken, params);
        __ERC721Holder_init();

        for (uint256 i; i < params.tokenIds.length; i += 1) {
            tokenIds.add(params.tokenIds[i]);
            freeTokenIds.add(params.tokenIds[i]);
        }
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
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
     * @dev this will request randome number via chainlink vrf coordinator
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
            freeTokenIds.remove(tokenIds_[0]);
            delete swaps[requestId];
            IERC721(nft).safeTransferFrom(requestor, address(this), swapId);
            IERC721(nft).safeTransferFrom(address(this), requestor, tokenIds_[0]);
            emit Swaped(requestor, requestId, tokenIds_[0]);
        } else if (requestor != address(0)) {
            for (uint256 i; i < randomWords.length; i += 1) {
                tokenIds_[i] = freeTokenIds.at(randomWords[i] % freeTokenIds.length());
                tokenIds.remove(tokenIds_[i]);
                freeTokenIds.remove(tokenIds_[i]);
                IERC721(nft).safeTransferFrom(address(this), requestor, tokenIds_[i]);
            }
            emit Redeemed(requestor, requestId, tokenIds_);
        } else {
            revert("Pool: INVALID_REQUEST_ID");
        }
        _distributeFee(requestor);
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
                IERC721(nft).safeTransferFrom(address(this), auction.winner, tokenId);
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
            IERC721(nft).safeTransferFrom(address(this), auction.winner, tokenId);
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
            IERC721(nft).safeTransferFrom(address(this), owner(), tokenIds.at(i));
    }
}
