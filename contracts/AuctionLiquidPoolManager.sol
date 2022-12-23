// solhint-disable
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./interfaces/IAuctionLiquidPoolManager.sol";
import "./AuctionLiquidPool721.sol";
import "./AuctionLiquidPool1155.sol";

contract AuctionLiquidPoolManager is IAuctionLiquidPoolManager, Ownable {
    address public pool721Template;
    address public pool1155Template;
    address public token;
    address[] public pools;

    event PoolCreated(address indexed owner_, address indexed pool_, address poolTemplate_);

    constructor(address token_) {
        require(token_ != address(0), "PoolManager: TOKEN_0x0");
        token = token_;
    }

    /**
     * @notice create pool contract locking nfts
     * @dev only nft owners can call this function to lock their own nfts
     * @return poolAddress address of generated pool
     */
    function createPool721(
        address nft_,
        uint256 lockPeriod_,
        uint256 duration_,
        uint256[] calldata tokenIds_,
        bool isLinear_,
        uint256 delta_,
        uint256 ratio_,
        uint256 randomFee_,
        uint256 tradingFee_,
        uint256 startPrice_
    ) external returns (address poolAddress) {
        require(pool721Template != address(0), "PoolManager: MISSING_VAULT_TEMPLATE");
        require(tokenIds_.length > 0, "PoolManager: INFOS_MISSING");

        uint256 cType = _getType(nft_);
        require(cType == 1, "PoolManager: INVALID_NFT_ADDRESS");

        poolAddress = Clones.clone(pool721Template);
        PoolParams memory params = PoolParams(
            msg.sender,
            nft_,
            lockPeriod_,
            duration_,
            tokenIds_,
            isLinear_,
            delta_,
            ratio_,
            randomFee_,
            tradingFee_,
            startPrice_
        );
        AuctionLiquidPool721 pool = AuctionLiquidPool721(poolAddress);
        pool.initialize(params);
        pool.transferOwnership(msg.sender);
        pools.push(poolAddress);

        for (uint256 i; i < params.tokenIds.length; i += 1)
            IERC721(nft_).safeTransferFrom(msg.sender, poolAddress, params.tokenIds[i]);

        emit PoolCreated(msg.sender, poolAddress, pool721Template);
    }

    /**
     * @notice create pool contract locking nfts
     * @dev only nft owners can call this function to lock their own nfts
     * @return poolAddress address of generated pool
     */
    function createPool1155(
        address nft_,
        uint256 lockPeriod_,
        uint256 duration_,
        uint256[] calldata tokenIds_,
        bool isLinear_,
        uint256 delta_,
        uint256 ratio_,
        uint256 randomFee_,
        uint256 tradingFee_,
        uint256 startPrice_
    ) external returns (address poolAddress) {
        require(pool1155Template != address(0), "PoolManager: MISSING_VAULT_TEMPLATE");
        require(tokenIds_.length > 0, "PoolManager: INFOS_MISSING");

        uint256 cType = _getType(nft_);
        require(cType == 2, "PoolManager: INVALID_NFT_ADDRESS");

        poolAddress = Clones.clone(pool1155Template);
        PoolParams memory params = PoolParams(
            msg.sender,
            nft_,
            lockPeriod_,
            duration_,
            tokenIds_,
            isLinear_,
            delta_,
            ratio_,
            randomFee_,
            tradingFee_,
            startPrice_
        );
        AuctionLiquidPool1155 pool = AuctionLiquidPool1155(poolAddress);
        pool.initialize(params);
        pool.transferOwnership(msg.sender);
        pools.push(poolAddress);

        for (uint256 i; i < params.tokenIds.length; i += 1)
            IERC1155(nft_).safeTransferFrom(msg.sender, poolAddress, params.tokenIds[i], 1, "");

        emit PoolCreated(msg.sender, poolAddress, pool1155Template);
    }

    /**
     * @notice set pool template
     * @dev only manager contract owner can call this function
     * @param poolTemplate_ new template address
     */
    function setPool721Template(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: 0x0");
        pool721Template = poolTemplate_;
    }

    /**
     * @notice set pool template
     * @dev only manager contract owner can call this function
     * @param poolTemplate_ new template address
     */
    function setPool1155Template(address poolTemplate_) external onlyOwner {
        require(poolTemplate_ != address(0), "PoolManager: 0x0");
        pool1155Template = poolTemplate_;
    }

    function mToken() external view override returns (IERC20Upgradeable) {
        return IERC20Upgradeable(token);
    }

    function maToken() external view override returns (maNFT) {
        return maNFT(token);
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
