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
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

import "./libraries/DecimalMath.sol";
import "./AuctionLiquidPoolManager.sol";
import "./maNFT.sol";

contract AuctionLiquidPool is
    OwnableUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using DecimalMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    AuctionLiquidPoolManager public manager;
    address public operator;

    address public nft;
    uint256 public createdAt;
    uint256 public lockPeriod;
    uint256 public duration;
    EnumerableSetUpgradeable.UintSet private tokenIds;
    bool public isLinear;
    uint256 public delta;
    uint256 public ratio;

    address lastBidder;
    uint256 lastBidAmount;

    mapping(uint256 => uint256) public startedAt;

    modifier onlyExistingId(uint256 tokenId) {
        require(tokenIds.contains(tokenId), "Pool: NON_EXISTENCE_NFT");
        _;
    }

    function initialize(PoolParams memory params, address operator_) public initializer {
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
        operator = operator_;
        nft = params.nft;
        lockPeriod = params.lockPeriod;
        duration = params.duration;
        isLinear = params.isLinear;
        delta = params.delta;
        ratio = params.ratio;
    }

    function redeem(address user, uint256 tokenId) external payable onlyExistingId(tokenId) {
        require(block.timestamp > createdAt + lockPeriod, "Pool: NFTS_UNLOCKED");
        require(msg.sender == operator, "Pool: NOT_OPERATOR");
        require(
            startedAt[tokenId] == 0 || startedAt[tokenId] + duration < block.timestamp,
            "Pool: LOCKED_NFT"
        );

        maNFT(manager.token()).burn(user, ratio);
        IERC721Upgradeable(nft).safeTransferFrom(address(this), user, tokenId);
        tokenIds.remove(tokenId);
    }

    function startAuction(uint256 tokenId) external onlyOwner onlyExistingId(tokenId) {
        startedAt[tokenId] = block.timestamp;
    }

    function endAuction(uint256 tokenId) external onlyOwner onlyExistingId(tokenId) {
        require(block.timestamp > startedAt[tokenId] + duration, "Pool: STILL_ACTIVE");

        startedAt[tokenId] = 0;
        tokenIds.remove(tokenId);
        maNFT(manager.token()).burn(
            address(this),
            IERC20Upgradeable(manager.token()).balanceOf(address(this))
        );
        IERC721Upgradeable(nft).safeTransferFrom(address(this), lastBidder, tokenId);
        payable(owner()).transfer(lastBidAmount);
    }

    function bid() external payable {
        require(block.timestamp > createdAt + duration, "Pool: EXPIRED");

        if (lastBidAmount == 0) {
            require(msg.value > 0, "Pool: EMPTY_BID");
            lastBidAmount = msg.value;
            IERC20Upgradeable(manager.token()).safeTransferFrom(
                msg.sender,
                address(this),
                lastBidAmount
            );
        } else {
            uint256 nextBidAmount = isLinear
                ? lastBidAmount + delta
                : lastBidAmount + lastBidAmount.decimalMul(delta);
            require(msg.value >= nextBidAmount, "Pool: TOO_LOW_BID");

            payable(lastBidder).transfer(lastBidAmount);
            if (msg.value > lastBidAmount) payable(msg.sender).transfer(msg.value - nextBidAmount);

            IERC20Upgradeable(manager.token()).safeTransfer(lastBidder, lastBidAmount);
            IERC20Upgradeable(manager.token()).safeTransferFrom(
                msg.sender,
                address(this),
                nextBidAmount
            );

            lastBidAmount = nextBidAmount;
        }
        lastBidder = msg.sender;
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
