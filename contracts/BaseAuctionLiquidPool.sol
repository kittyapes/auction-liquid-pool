// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/DecimalMath.sol";
import "./interfaces/IMappingToken.sol";
import "./interfaces/IBaseAuctionLiquidPool.sol";
import "./interfaces/IAuctionLiquidPoolManager.sol";
import "./chainlink/VRFConsumerBaseUpgradeable.sol";

abstract contract BaseAuctionLiquidPool is
    IBaseAuctionLiquidPool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    VRFConsumerBaseUpgradeable
{
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    event RedeemRequested(address indexed account, bytes32[] requestIds);
    event SwapRequested(address indexed account, uint256 tokenId, bytes32 requestId);
    event Redeemed(address indexed account, bytes32 requestId, uint256 tokenId);
    event Swaped(address indexed account, bytes32 requestId, uint256 tokenId);

    // keyHash being used for chainlink vrf coordinate
    bytes32 internal keyHash;
    // LINK token amount charging for fee
    uint256 internal fee;

    IAuctionLiquidPoolManager public manager;

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

    // random request id -> redeem requester
    mapping(bytes32 => address) public redeemers;
    // random request id -> swap requester
    mapping(bytes32 => uint256) public swaps;
    mapping(bytes32 => address) public swapper;

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
        address coordinator,
        address link,
        address token,
        address mToken,
        PoolParams memory params
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();
        __VRFConsumerBase_init(coordinator, link);
        // Etherscan
        // 0x271682DEB8C4E0901D1a1550aD2e64D568E69909, // VRF Coordinator Etherscan
        // 0x514910771AF9Ca656af840dff83E8264EcF986CA // LINK Token Etherscan

        keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
        fee = 25e17; // 0.25 LINK

        // Etherscan
        // keyHash = 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef;
        // fee = 1e14; // 0.0001 LINK

        manager = IAuctionLiquidPoolManager(msg.sender);
        dexToken = token;
        mappingToken = mToken;
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

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function redeem(uint256 count) external virtual returns (bytes32[] memory requestIds);

    /**
     * @notice user can swap random NFT by paying ratio amount of maNFT
     * @dev this will request randome number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function swap(uint256 tokenId) external virtual returns (bytes32 requestId);

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
     * @notice cancel auction for tokenId
     * @dev only pool owner can end the auction
     * - return bid amounts to bidder,
     * - lock NFT back to contract
     * @param tokenId targeted token Id
     */
    function cancelAuction(uint256 tokenId) external virtual;

    /**
     * @notice bid to the auction for tokenId
     * @dev any user can bid with ratio amount of maNFT and customized amount of ether
     * bid flow is like this
     * first user comes with ratio amount of maNFT and more than 0.1 amount of ether
     * for next bids, ether amount should be higher than the amount determined by price curve and delta,
     * maNFT amount would be always the same - ratio.
     * @param tokenId targeted token Id
     */
    function bid(uint256 tokenId) external payable virtual;

    function getTokenIds() external view virtual returns (uint256[] memory tokenIds_);

    function recover() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function recoverTokens(IERC20 token) external onlyOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    function recoverNFTs() external virtual;

    function _distributeFee(address account) internal {
        uint256 totalFee = ratio.decimalMul(randomFee);
        for (uint256 i; i < feeTypes.length; i += 1) {
            uint256 feeAmount = totalFee.decimalMul(feeValues[i]);
            address to;
            if (feeTypes[i] == FeeType.PROJECT) to = owner();
            else if (feeTypes[i] == FeeType.AMM_POOL)
                to = IMappingToken(mappingToken).uniswapPool();
            else if (feeTypes[i] == FeeType.NFT_HOLDERS) to = manager.treasury();
            else to = owner();
            IERC20(mappingToken).safeTransferFrom(account, to, feeAmount);
        }
        IMappingToken(mappingToken).burnFrom(account, ratio - totalFee);
    }
}
