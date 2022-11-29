// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

import "./libraries/DecimalMath.sol";
import "./AuctionLiquidPoolManager.sol";
import "./maNFT.sol";

contract AuctionLiquidPool is
    OwnableUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable,
    VRFConsumerBase
{
    using DecimalMath for uint256;
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event RedeemReqeusted(address indexed account, bytes32 indexed requestId);

    // keyHash being used for chainlink vrf coordinate
    bytes32 private keyHash;
    // LINK token amount charging for fee
    uint256 private fee;

    AuctionLiquidPoolManager public manager;

    address public nft;
    uint256 public createdAt;
    uint256 public lockPeriod;
    uint256 public duration;
    EnumerableSetUpgradeable.UintSet private tokenIds;
    EnumerableSetUpgradeable.UintSet private freeTokenIds;
    bool public isLinear;
    uint256 public delta;
    uint256 public ratio;
    uint256 public randomFee;
    uint256 public tradingFee;
    uint256 public startPrice;

    // random request id -> redeem requester
    mapping(bytes32 => address) public redeemers;

    struct Auction {
        // last highest bidder
        address winner;
        // ether amount bidded
        uint256 bidAmount;
        // auction start time
        uint256 startedAt;
    }
    mapping(uint256 => Auction) public auctions;

    constructor(address coordinator, address link)
        VRFConsumerBase(coordinator, link)
    // 0x271682DEB8C4E0901D1a1550aD2e64D568E69909, // VRF Coordinator Etherscan
    // 0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token Etherscan
    {
        keyHash = 0x0476f9a745b61ea5c0ab224d3a6e4c99f0b02fce4da01143a4f70aa80ae76e8a;
        fee = 1e17; // 0.1 LINK

        // Etherscan
        // keyHash = 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef;
        // fee = 1e14; // 0.0001 LINK
    }

    modifier onlyExistingId(uint256 tokenId) {
        require(tokenIds.contains(tokenId), "Pool: NON_EXISTENCE_NFT");
        _;
    }

    function initialize(PoolParams memory params) public initializer {
        __Ownable_init();
        __ERC721Holder_init();
        __ReentrancyGuard_init();

        for (uint256 i; i < params.tokenIds.length; i += 1) {
            tokenIds.add(params.tokenIds[i]);
            freeTokenIds.add(params.tokenIds[i]);
        }
        manager = AuctionLiquidPoolManager(msg.sender);
        nft = params.nft;
        lockPeriod = params.lockPeriod;
        duration = params.duration;
        isLinear = params.isLinear;
        delta = params.delta;
        ratio = params.ratio;
        randomFee = params.randomFee;
        tradingFee = params.tradingFee;
        startPrice = params.startPrice;
        createdAt = block.timestamp;
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function redeem() external returns (bytes32 requestId) {
        require(block.timestamp < createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(LINK.balanceOf(address(this)) >= fee, "Pool: INSUFFICIENT_LINK");
        require(freeTokenIds.length() > 0, "Pool: NO_FREE_NFTS");

        requestId = requestRandomness(keyHash, fee);
        redeemers[requestId] = msg.sender;
        emit RedeemReqeusted(msg.sender, requestId);
    }

    /**
     * @notice above {redeem} function makes random number generation request
     * @param requestId above {redeem} function returns requestId per request
     * @param randomness generated random number to determine which tokenId to redeem
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 tokenId = freeTokenIds.at(randomness % freeTokenIds.length());
        address redeemer = redeemers[requestId];
        tokenIds.remove(tokenId);
        freeTokenIds.remove(tokenId);
        delete redeemers[requestId];

        maNFT(manager.token()).burn(redeemer, ratio);
        IERC721Upgradeable(nft).safeTransferFrom(address(this), redeemer, tokenId);
    }

    /**
     * @notice start auction for tokenId
     * @dev any user can start auction for a targeted NFT
     * @param tokenId targeted token Id
     */
    function startAuction(uint256 tokenId) external onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        if (auction.startedAt > 0) {
            require(block.timestamp > auction.startedAt + duration, "Pool: STILL_ACTIVE");
            delete auctions[tokenId];

            if (auction.bidAmount > 0) {
                tokenIds.remove(tokenId);
                maNFT(manager.token()).burn(address(this), ratio);
                IERC721Upgradeable(nft).safeTransferFrom(address(this), auction.winner, tokenId);
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
    function endAuction(uint256 tokenId) external onlyOwner onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        require(
            auctions[tokenId].startedAt > 0 &&
                block.timestamp > auctions[tokenId].startedAt + duration,
            "Pool: STILL_ACTIVE"
        );

        delete auctions[tokenId];
        if (auction.bidAmount > 0) {
            tokenIds.remove(tokenId);
            maNFT(manager.token()).burn(address(this), ratio);
            IERC721Upgradeable(nft).safeTransferFrom(address(this), auction.winner, tokenId);
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
    function cancelAuction(uint256 tokenId) external onlyOwner onlyExistingId(tokenId) {
        Auction memory auction = auctions[tokenId];
        delete auctions[tokenId];
        freeTokenIds.add(tokenId);
        if (auction.bidAmount > 0) {
            payable(auction.winner).transfer(auction.bidAmount);
            IERC20Upgradeable(manager.token()).safeTransfer(auction.winner, ratio);
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
    function bid(uint256 tokenId) external payable {
        Auction storage auction = auctions[tokenId];
        require(block.timestamp < auction.startedAt + duration, "Pool: EXPIRED");
        require(msg.value >= startPrice, "Pool: TOO_LOW_BID");

        if (auction.bidAmount == 0) {
            IERC20Upgradeable(manager.token()).safeTransferFrom(msg.sender, address(this), ratio);
            auction.bidAmount = msg.value;
            // if (msg.value > startPrice) payable(msg.sender).transfer(msg.value - startPrice);
        } else {
            uint256 nextBidAmount = isLinear
                ? auction.bidAmount + delta
                : auction.bidAmount + auction.bidAmount.decimalMul(delta);
            require(msg.value >= nextBidAmount, "Pool: INSUFFICIENT_BID");
            if (msg.value > nextBidAmount) payable(msg.sender).transfer(msg.value - nextBidAmount);
            auction.bidAmount = nextBidAmount;

            IERC20Upgradeable(manager.token()).transfer(auction.winner, ratio);
            IERC20Upgradeable(manager.token()).safeTransferFrom(msg.sender, address(this), ratio);
        }
        auction.winner = msg.sender;
    }

    function recover() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function recoverTokens(IERC20Upgradeable token) external onlyOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    function recoverNFTs() external onlyOwner {
        for (uint256 i; i < tokenIds.length(); i += 1)
            IERC721Upgradeable(nft).safeTransferFrom(address(this), owner(), tokenIds.at(i));
    }
}
