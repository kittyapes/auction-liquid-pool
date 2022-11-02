import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';

describe('Auction Liquid Pool Manager', function () {
  let manager: Contract;
  let maNFT: Contract;
  let nft: Contract;

  beforeEach(async () => {

    const VRFCoordinatorFactory = await ethers.getContractFactory("VRFCoordinatorMock");
    const LinkFactory = await ethers.getContractFactory("LinkToken");
    const link = await LinkFactory.deploy();
    const coordinator = await VRFCoordinatorFactory.deploy(link.address);

    const MockTokenFactory = await ethers.getContractFactory('MockToken');
    const MockNFTFactory = await ethers.getContractFactory('MockNFT');
    maNFT = await MockTokenFactory.deploy();
    nft = await MockNFTFactory.deploy();

    const AuctionLiquidPoolFactory = await ethers.getContractFactory('AuctionLiquidPool');
    const AuctionLiquidPoolManagerFactory = await ethers.getContractFactory(
      'AuctionLiquidPoolManager',
    );
    manager = await AuctionLiquidPoolManagerFactory.deploy(maNFT.address);
    const poolTemplate = await AuctionLiquidPoolFactory.deploy(coordinator.address, link.address);
    await manager.setPoolTemplate(poolTemplate.address);

    await nft.mint(3);
    await nft.setApprovalForAll(manager.address, true);
  });

  it('#createPool', async () => {
    const params = [nft.address, 86400 * 7, 86400, [0, 1, 2], false, 10, 100];

    const tx = await manager.createPool(...params);
    const receipt = await tx.wait();
    expect(await manager.pools(0)).to.eq(receipt.events[receipt.events.length - 1].args.pool_);
  });
});
