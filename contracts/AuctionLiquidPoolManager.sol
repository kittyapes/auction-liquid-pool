// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./interfaces/IAuctionLiquidPool.sol";
import "./interfaces/IMappingToken.sol";

contract AuctionLiquidPoolManager is IBaseAuctionLiquidPool, OwnableUpgradeable {
    address private constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address public vrfCoordinator;
    address public dexToken;
    address public treasury;

    address public mTokenTemplate;
    address public pool721Template;
    address public pool1155Template;
    address[] public pools;

    event PoolCreated(address indexed owner_, address indexed pool_, address poolTemplate_);

    function initialize(address coordinator_, address token_) public initializer {
        __Ownable_init();

        vrfCoordinator = coordinator_;
        dexToken = token_;
    }

    /**
     * @notice create pool contract locking nfts
     * @dev only nft owners can call this function to lock their own nfts
     * @return poolAddress address of generated pool
     */
    function createPool(PoolParams memory params) external returns (address poolAddress) {
        require(mTokenTemplate != address(0), "PoolManager: TOKEN_TEMPLATE_UNSET");
        uint256 cType = _getType(params.nft);
        require(cType > 0, "PoolManager: INVALID_NFT_ADDRESS");
        require(
            params.feeTypes.length == params.feeValues.length,
            "PoolManager: MISMATCH_FEE_INFO"
        );

        uint16 feeSum;
        bool hasNFTHolderType;
        unchecked {
            for (uint256 i; i < params.feeTypes.length; i += 1) {
                feeSum += params.feeValues[i];
                hasNFTHolderType = hasNFTHolderType || (params.feeTypes[i] == FeeType.NFT_HOLDERS);
            }
        }
        require(!hasNFTHolderType || treasury != address(0), "PoolManager: TREASURY_UNSET");
        require(feeSum == 1000, "PoolManager: INSUFFICIENT_FEE_VALUES");

        uint256 amount = params.tokenIds.length * params.ratio;
        string memory symbol = string(abi.encodePacked("MT_", params.name));
        address mTokenAddress = Clones.clone(mTokenTemplate);
        IMappingToken mToken = IMappingToken(mTokenAddress);
        mToken.initialize(params.name, symbol, amount);
        mToken.setPair(IUniswapV2Factory(UNIV2_FACTORY).createPair(mTokenAddress, dexToken));
        mToken.transferOwnership(msg.sender);

        mToken.approve(UNIV2_ROUTER, amount);
        IMappingToken(dexToken).approve(UNIV2_ROUTER, amount);
        IUniswapV2Router01(UNIV2_ROUTER).addLiquidity(
            mTokenAddress,
            dexToken,
            amount,
            amount,
            0,
            0,
            msg.sender,
            block.timestamp + 1000
        );

        params.owner = msg.sender;
        if (cType == 1) {
            require(pool721Template != address(0), "PoolManager: 721_TEMPLATE_UNSET");
            poolAddress = Clones.clone(pool721Template);
            IAuctionLiquidPool pool = IAuctionLiquidPool(poolAddress);
            pool.initialize(vrfCoordinator, dexToken, mTokenAddress, params);
            pool.transferOwnership(msg.sender);

            for (uint256 i; i < params.tokenIds.length; i += 1)
                IERC721(params.nft).safeTransferFrom(msg.sender, poolAddress, params.tokenIds[i]);
        } else {
            require(pool1155Template != address(0), "PoolManager: 1155_TEMPLATE_UNSET");
            poolAddress = Clones.clone(pool1155Template);
            IAuctionLiquidPool pool = IAuctionLiquidPool(poolAddress);
            pool.initialize(vrfCoordinator, dexToken, mTokenAddress, params);
            pool.transferOwnership(msg.sender);

            for (uint256 i; i < params.tokenIds.length; i += 1)
                IERC1155(params.nft).safeTransferFrom(
                    msg.sender,
                    poolAddress,
                    params.tokenIds[i],
                    1,
                    ""
                );
        }

        pools.push(poolAddress);
        emit PoolCreated(msg.sender, poolAddress, [pool721Template, pool1155Template][cType - 1]);
    }

    /**
     * @notice set treasury
     * @dev only contract owner can call this function
     * @param treasury_ new treasury address
     */
    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "PoolManager: TREASURY_0x0");
        treasury = treasury_;
    }

    /**
     * @notice set token template
     * @dev only contract owner can call this function
     * @param tokenTemplate_ new token template address
     */
    function setTokenTemplate(address tokenTemplate_) external onlyOwner {
        require(tokenTemplate_ != address(0), "PoolManager: TOKEN_TEMPLATE_0x0");
        mTokenTemplate = tokenTemplate_;
    }

    /**
     * @notice set 721 pool template
     * @dev only contract owner can call this function
     * @param poolTemplate_ new template address
     */
    function setPool721Template(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: NFT721_TEMPLATE_0x0");
        pool721Template = poolTemplate_;
    }

    /**
     * @notice set 1155 pool template
     * @dev only contract owner can call this function
     * @param poolTemplate_ new template address
     */
    function setPool1155Template(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: NFT1155_TEMPLATE_0x0");
        pool1155Template = poolTemplate_;
    }

    function _getType(address collection) private view returns (uint8) {
        uint256 csize;
        assembly {
            csize := extcodesize(collection)
        }
        if (csize == 0) return 0;

        bool is721;
        try IERC165(collection).supportsInterface(type(IERC721).interfaceId) returns (
            bool result1
        ) {
            is721 = result1;
            if (result1) return 1;
            try IERC165(collection).supportsInterface(type(IERC1155).interfaceId) returns (
                bool result2
            ) {
                return result2 ? 2 : 0;
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }
}
