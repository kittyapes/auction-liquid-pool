import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { constants, Contract, utils } from 'ethers';

describe('Auction Liquid Pool Manager', function () {
  let manager: Contract;
  let nft: Contract;

  beforeEach(async () => {
    const VRFCoordinatorFactory = await ethers.getContractFactory('VRFCoordinatorMock');
    const LinkFactory = await ethers.getContractFactory('LinkToken');
    const link = await LinkFactory.deploy();
    const coordinator = await VRFCoordinatorFactory.deploy(link.address);

    const DexTokenFactory = await ethers.getContractFactory('DexToken');
    const Mock721NFTFactory = await ethers.getContractFactory('Mock721NFT');
    const dexToken = await DexTokenFactory.deploy();
    nft = await Mock721NFTFactory.deploy();

    const AuctionLiquidPoolManagerFactory = await ethers.getContractFactory(
      'AuctionLiquidPoolManager',
    );
    manager = await upgrades.deployProxy(AuctionLiquidPoolManagerFactory, [
      coordinator.address,
      link.address,
      dexToken.address,
    ]);

    const MappingTokenFactory = await ethers.getContractFactory('MappingToken');
    const AuctionLiquidPool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
    const mToken = await MappingTokenFactory.deploy();
    const pool721Template = await AuctionLiquidPool721Factory.deploy();
    await manager.setTokenTemplate(mToken.address);
    await manager.setPool721Template(pool721Template.address);

    await dexToken.transfer(manager.address, utils.parseEther('10000'));
    await nft.mint(3);
    await nft.setApprovalForAll(manager.address, true);
  });

  it('#createPool', async () => {
    const params = [
      'HypeX',
      constants.AddressZero,
      nft.address,
      86400 * 7,
      86400,
      [0, 1, 2],
      false,
      1000,
      utils.parseEther('2'),
      50,
      10,
      utils.parseEther('0.01'),
      [0],
      [1000],
    ];

    const tx = await manager.createPool(params);
    const receipt = await tx.wait();
    expect(await manager.pools(0)).to.eq(receipt.events[receipt.events.length - 1].args.pool_);
  });
});
