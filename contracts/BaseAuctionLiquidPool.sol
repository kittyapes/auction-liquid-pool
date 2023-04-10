// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/DecimalMath.sol";
import "./interfaces/IMappingToken.sol";
import "./interfaces/IBaseAuctionLiquidPool.sol";
import "./interfaces/IAuctionLiquidPoolManager.sol";

abstract contract BaseAuctionLiquidPool is
    IBaseAuctionLiquidPool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    event NFTsLocked(address indexed account, uint256[] tokenIds);
    event Redeemed(address indexed account, uint256[] tokenIds);
    event Swaped(address indexed account, uint256 srcTokenId, uint256 dstTokenId);
    event AuctionStarted(uint256 indexed tokenId, address indexed starter);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed tokenId, address indexed winner);

    IAuctionLiquidPoolManager public manager;

    string public logo;
    address public dexToken;
    address public mappingToken;
    address public nft;
    uint64 public createdAt;
    uint64 public lockPeriod;
    uint64 public duration;
    bool public isLinear;
    uint256 public delta;
    uint256 public ratio;
    uint16 public randomFee;
    uint16 public tradingFee;
    uint256 public startPrice;
    FeeType[] public feeTypes;
    uint16[] public feeValues;

    struct Auction {
        // last highest bidder
        address winner;
        // ether amount bidded
        uint256 bidAmount;
        // auction start time
        uint256 startedAt;
    }
    mapping(uint256 => Auction) public auctions;

    function __BaseAuctionLiquidPool_init(
        address token,
        address mToken,
        PoolParams memory params
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();

        assert(token != address(0));
        assert(mToken != address(0));
        assert(params.nft != address(0));
        assert(params.lockPeriod > 0);
        assert(params.duration > 0);
        assert(params.delta > 0);
        assert(params.ratio >= 1 ether);

        manager = IAuctionLiquidPoolManager(msg.sender);
        dexToken = token;
        mappingToken = mToken;
        logo = params.logo;
        nft = params.nft;
        lockPeriod = params.lockPeriod;
        duration = params.duration;
        isLinear = params.isLinear;
        delta = params.delta;
        ratio = params.ratio;
        randomFee = params.randomFee;
        tradingFee = params.tradingFee;
        startPrice = params.startPrice;
        createdAt = uint64(block.timestamp);
        feeTypes = params.feeTypes;
        feeValues = params.feeValues;
    }

    /// @notice user can redeem random NFT by paying ratio amount of maNFT
    function redeem(uint32) external virtual returns (uint256[] memory);

    /// @notice user can swap random NFT by paying ratio amount of maNFT
    function swap(uint256) external virtual returns (uint256);

    /**
     * @notice start auction for tokenId
     * @dev any user can start auction for a targeted NFT
     * @param tokenId targeted token Id
     */
    function startAuction(uint256 tokenId) external virtual;

    /**
     * @notice end auction for tokenId
     * @dev only pool owner can end the auction
     * - transfer NFT to auction winner,
     * - burn staked maNFT
     * - transfer ether to pool owner as premium
     * @param tokenId targeted token Id
     */
    function endAuction(uint256 tokenId) external virtual;

    /**
     * @notice bid to the auction for tokenId
     * @dev any user can bid with ratio amount of maNFT and customized amount of ether
     * bid flow is like this
     * first user comes with ratio amount of maNFT and more than 0.1 amount of ether
     * for next bids, ether amount should be higher than the amount determined by price curve and delta,
     * maNFT amount would be always the same - ratio.
     * @param tokenId targeted token Id
     */
    function bid(uint256 tokenId) external virtual;

    function recover() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function recoverTokens(IERC20 token) external onlyOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    function recoverNFTs() external virtual;

    function lockNFTs(uint256[] calldata) external virtual;

    function getTokenIds() external view virtual returns (uint256[] memory tokenIds_);

    function getFreeTokenIds() external view virtual returns (uint256[] memory tokenIds_);

    function getFeeTypes() external view returns (FeeType[] memory feeTypes_) {
        feeTypes_ = new FeeType[](feeTypes.length);
        unchecked {
            for (uint256 i; i < feeTypes_.length; ++i) feeTypes_[i] = feeTypes[i];
        }
    }

    function getFeeValues() external view returns (uint16[] memory feeValues_) {
        feeValues_ = new uint16[](feeValues.length);
        unchecked {
            for (uint256 i; i < feeValues_.length; ++i) feeValues_[i] = feeValues[i];
        }
    }

    function _distributeFee(address account, uint256 count) internal {
        uint256 totalFee = (count * ratio).decimalMul(randomFee);
        for (uint256 i; i < feeTypes.length; ++i) {
            uint256 feeAmount = totalFee.decimalMul(feeValues[i]);
            address to;
            if (feeTypes[i] == FeeType.PROJECT) to = owner();
            else if (feeTypes[i] == FeeType.AMM_POOL)
                to = IMappingToken(mappingToken).uniswapPool();
            else if (feeTypes[i] == FeeType.NFT_HOLDERS) to = manager.treasury();
            else to = owner();
            IERC20(mappingToken).safeTransferFrom(account, to, feeAmount);
        }
        IMappingToken(mappingToken).burnFrom(account, (count * ratio) - totalFee);
    }
}
