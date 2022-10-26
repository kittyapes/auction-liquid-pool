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
    bool public isLinear;
    uint256 public delta;
    uint256 public ratio;

    // random request id -> redeem requester
    mapping(bytes32 => address) public redeemers;

    struct Auction {
        // last highest bidder
        address winner;
        // maNFT token amount bidded
        uint256 bidAmount;
        // ether amount bidded
        uint256 etherAmount;
        // auction start time
        uint256 startedAt;
    }
    mapping(uint256 => Auction) public auctions;

    constructor()
        VRFConsumerBase(
            0x271682DEB8C4E0901D1a1550aD2e64D568E69909, // VRF Coordinator Etherscan
            0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token Etherscan
        )
    {
        keyHash = 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef; // Etherscan
        fee = 1e14; // 0.0001 LINK
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
            IERC721Upgradeable(nft).safeTransferFrom(
                params.owner,
                address(this),
                params.tokenIds[i]
            );
            tokenIds.add(params.tokenIds[i]);
        }
        manager = AuctionLiquidPoolManager(msg.sender);
        nft = params.nft;
        lockPeriod = params.lockPeriod;
        duration = params.duration;
        isLinear = params.isLinear;
        delta = params.delta;
        ratio = params.ratio * 1 ether;
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function redeem() external {
        require(block.timestamp > createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(LINK.balanceOf(address(this)) >= fee, "Pool: INSUFFICIENT_LINK");

        bytes32 requestId = requestRandomness(keyHash, fee);
        redeemers[requestId] = msg.sender;
    }

    /**
     * @notice above {redeem} function makes random number generation request
     * @param requestId above {redeem} function returns requestId per request
     * @param randomness generated random number to determine which tokenId to redeem
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 tokenId = tokenIds.at(randomness % tokenIds.length());
        require(
            auctions[tokenId].startedAt == 0 ||
                auctions[tokenId].startedAt + duration < block.timestamp,
            "Pool: LOCKED_NFT"
        );

        address redeemer = redeemers[requestId];
        tokenIds.remove(tokenId);
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
        require(auctions[tokenId].startedAt == 0, "Pool: ALREADY_IN_AUCTION");
        auctions[tokenId].startedAt = block.timestamp;
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
        tokenIds.remove(tokenId);
        maNFT(manager.token()).burn(address(this), auction.bidAmount);
        IERC721Upgradeable(nft).safeTransferFrom(address(this), auction.winner, tokenId);
        payable(owner()).transfer(auction.etherAmount);
    }

    /**
     * @notice bid to the auction for tokenId
     * @dev any user can bid with maNFT and ether
     * bid flow is like this
     * first user comes with certain maNFT amount, takes min of incoming amount and ratio
     * for next bids, maNFT amount should be higher than the amount determined by price curve and delta,
     * if maNFT amount reaches ratio, start accepting ether
     * later on, take maNFT for ratio amount only and accept higher ether only
     * @param tokenId targeted token Id
     * @param amount of maNFT to bid
     */
    function bid(uint256 tokenId, uint256 amount) external payable {
        Auction storage auction = auctions[tokenId];
        require(block.timestamp > auction.startedAt + duration, "Pool: EXPIRED");

        if (auction.bidAmount == 0) {
            uint256 bidAmount = MathUpgradeable.min(amount, ratio);
            IERC20Upgradeable(manager.token()).safeTransferFrom(
                msg.sender,
                address(this),
                bidAmount
            );
            if (msg.value > 0) payable(msg.sender).transfer(msg.value);
            auction.bidAmount = bidAmount;
        } else if (auction.bidAmount < ratio) {
            uint256 nextBidAmount = isLinear
                ? auction.bidAmount + delta
                : auction.bidAmount + auction.bidAmount.decimalMul(delta);
            require(amount >= nextBidAmount, "Pool: TOO_LOW_BID");

            uint256 bidAmount = MathUpgradeable.min(nextBidAmount, ratio);
            IERC20Upgradeable(manager.token()).transfer(auction.winner, auction.bidAmount);
            IERC20Upgradeable(manager.token()).safeTransferFrom(
                msg.sender,
                address(this),
                bidAmount
            );
            if (msg.value > 0) payable(msg.sender).transfer(msg.value);
            auction.bidAmount = bidAmount;
        } else {
            require(msg.value > auction.etherAmount, "Pool: TOO_LOW_ETH");
            IERC20Upgradeable(manager.token()).transfer(auction.winner, ratio);
            IERC20Upgradeable(manager.token()).safeTransferFrom(msg.sender, address(this), ratio);
            auction.etherAmount = msg.value;
            if (auction.etherAmount > 0) payable(auction.winner).transfer(auction.etherAmount);
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
