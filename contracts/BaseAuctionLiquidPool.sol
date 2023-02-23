// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

import "./libraries/DecimalMath.sol";
import "./interfaces/IMappingToken.sol";
import "./interfaces/IBaseAuctionLiquidPool.sol";
import "./interfaces/IAuctionLiquidPoolManager.sol";
import "./chainlink/LinkTokenInterface.sol";

abstract contract BaseAuctionLiquidPool is
    IBaseAuctionLiquidPool,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    event NFTsLocked(uint256[] tokenIds);
    event RedeemRequested(address indexed account, uint256 requestId);
    event SwapRequested(address indexed account, uint256 tokenId, uint256 requestId);
    event Redeemed(address indexed account, uint256 requestId, uint256[] tokenIds);
    event Swaped(address indexed account, uint256 requestId, uint256 tokenId);
    event AuctionStarted(uint256 indexed tokenId, address indexed starter);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event AuctionEnded(uint256 indexed tokenId, address indexed winner);
    error OnlyCoordinatorCanFulfill(address have, address want);

    address private vrfCoordinator; // goerli: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D, etherscan: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909
    address private constant LINK = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB; // 0x514910771AF9Ca656af840dff83E8264EcF986CA
    bytes32 private constant s_keyHash =
        0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15; // 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef
    uint16 private constant s_requestConfirmations = 3;
    uint32 private constant s_callbackGasLimit = 2500000;
    uint64 public s_subscriptionId;

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
    mapping(uint256 => address) public redeemers;
    // random request id -> swap requester
    mapping(uint256 => uint256) public swaps;
    mapping(uint256 => address) public swapper;

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

        vrfCoordinator = coordinator;
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

        createNewSubscription();
    }

    function chargeLINK(uint256 amount) external {
        IERC20(LINK).safeTransferFrom(msg.sender, address(this), amount);
        LinkTokenInterface(LINK).transferAndCall(
            vrfCoordinator,
            amount,
            abi.encode(s_subscriptionId)
        );
    }

    /**
     * @notice fulfillRandomness handles the VRF response. Your contract must
     * @notice implement it. See "SECURITY CONSIDERATIONS" above for important
     * @notice principles to keep in mind when implementing your fulfillRandomness
     * @notice method.
     *
     * @dev VRFConsumerBaseV2 expects its subcontracts to have a method with this
     * @dev signature, and will call it once it has verified the proof
     * @dev associated with the randomness. (It is triggered via a call to
     * @dev rawFulfillRandomness, below.)
     *
     * @param requestId The Id initially returned by requestRandomWords
     * @param randomWords the VRF output expanded to the requested number of words
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;

    // rawFulfillRandomness is called by VRFCoordinator when it receives a valid VRF
    // proof. rawFulfillRandomness then calls fulfillRandomness, after validating
    // the origin of the call
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        if (msg.sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, vrfCoordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @notice user can redeem random NFT by paying ratio amount of maNFT
     * @dev this will request random number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
    function redeem(uint32) external virtual returns (uint256);

    /**
     * @notice user can swap random NFT by paying ratio amount of maNFT
     * @dev this will request random number via chainlink vrf coordinator
     * requested random number will be retrieved by following {fulfillRandomness}
     */
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

    function manageConsumers(address consumer, bool add) external onlyOwner {
        add
            ? VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(s_subscriptionId, consumer)
            : VRFCoordinatorV2Interface(vrfCoordinator).removeConsumer(s_subscriptionId, consumer);
    }

    function cancelSubscription() external onlyOwner {
        VRFCoordinatorV2Interface(vrfCoordinator).cancelSubscription(s_subscriptionId, owner());
        s_subscriptionId = 0;
    }

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

    function requestRandomWords(uint32 numWords) internal returns (uint256) {
        return
            VRFCoordinatorV2Interface(vrfCoordinator).requestRandomWords(
                s_keyHash,
                s_subscriptionId,
                s_requestConfirmations,
                s_callbackGasLimit,
                numWords
            );
    }

    // Create a new subscription when the contract is initially deployed.
    function createNewSubscription() private {
        s_subscriptionId = VRFCoordinatorV2Interface(vrfCoordinator).createSubscription();
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(s_subscriptionId, address(this));
    }
}
