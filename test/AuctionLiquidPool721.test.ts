import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber, constants, Contract, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { increaseTime } from './utils';

describe('Auction Liquid Pool 721', function () {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let pool: Contract;
  let nft: Contract;
  let coordinator: Contract;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    const VRFCoordinatorFactory = await ethers.getContractFactory('VRFCoordinatorMock');
    const LinkFactory = await ethers.getContractFactory('LinkToken');
    const link = await LinkFactory.deploy();
    coordinator = await VRFCoordinatorFactory.deploy(link.address);

    const DexTokenFactory = await ethers.getContractFactory('DexToken');
    const Mock721NFTFactory = await ethers.getContractFactory('Mock721NFT');
    const dexToken = await DexTokenFactory.deploy();
    nft = await Mock721NFTFactory.deploy();

    const AuctionLiquidPoolManagerFactory = await ethers.getContractFactory(
      'AuctionLiquidPoolManager',
    );
    const manager = await upgrades.deployProxy(AuctionLiquidPoolManagerFactory, [
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
    await nft.mint(4);
    await nft.setApprovalForAll(manager.address, true);

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
      utils.parseEther('0.1'),
    ];
    const tx = await manager.createPool(params);
    const receipt = await tx.wait();
    pool = await AuctionLiquidPool721Factory.attach(
      receipt.events[receipt.events.length - 1].args.pool_,
    );
    const mappingToken = await MappingTokenFactory.attach(await pool.mappingToken());
    await mappingToken.mint(owner.address, utils.parseEther('100'));
    await mappingToken.mint(alice.address, utils.parseEther('100'));
    await mappingToken.mint(bob.address, utils.parseEther('100'));
    await mappingToken.connect(owner).approve(pool.address, utils.parseEther('100'));
    await mappingToken.connect(alice).approve(pool.address, utils.parseEther('100'));
    await mappingToken.connect(bob).approve(pool.address, utils.parseEther('100'));
    await link.transfer(pool.address, utils.parseEther('10'));
    await nft.setApprovalForAll(pool.address, true);

    await pool.startAuction(0);
  });

  it('#auction', async () => {
    await expect(pool.connect(alice).bid(0, { value: utils.parseEther('0.01') })).revertedWith(
      'Pool: TOO_LOW_BID',
    );
    await pool.connect(alice).bid(0, { value: utils.parseEther('1') });
    let auction = await pool.auctions(0);
    expect(auction[0]).to.eq(alice.address);
    await expect(pool.connect(bob).bid(0, { value: utils.parseEther('1.5') })).revertedWith(
      'Pool: INSUFFICIENT_BID',
    );
    await pool.connect(bob).bid(0, { value: utils.parseEther('2') });
    auction = await pool.auctions(0);
    expect(auction[0]).to.eq(bob.address);
    const ethBalance = await ethers.provider.getBalance(owner.address);
    await increaseTime(BigNumber.from('86400'));
    await pool.endAuction(0);
    expect(await nft.ownerOf(0)).to.eq(bob.address);
    expect(await ethers.provider.getBalance(owner.address)).to.closeTo(
      ethBalance.add(auction[1]),
      utils.parseEther('0.0002'),
      '',
    );
  });

  it('#redeem', async () => {
    const tx = await pool.connect(owner).redeem(1);
    const receipt = await tx.wait();
    const requestId = receipt.events[receipt.events.length - 1].args.requestIds[0];
    await coordinator.callBackWithRandomness(requestId, 123456, pool.address);
    expect(await nft.ownerOf(2)).to.eq(owner.address);
  });

  it('#swap', async () => {
    const tx = await pool.connect(owner).swap(3);
    const receipt = await tx.wait();
    const requestId = receipt.events[receipt.events.length - 1].args.requestId;
    await coordinator.callBackWithRandomness(requestId, 123456, pool.address);
    expect(await nft.ownerOf(3)).to.eq(pool.address);
    expect(await nft.ownerOf(2)).to.eq(owner.address);
  });
});
