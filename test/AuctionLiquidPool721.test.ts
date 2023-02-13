import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber, constants, Contract, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { increaseTime } from './utils';

describe('Auction Liquid Pool 721', function () {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let dexToken: Contract;
  let mappingToken: Contract;
  let nft: Contract;
  let pool: Contract;
  let coordinator: Contract;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    const VRFCoordinatorFactory = await ethers.getContractFactory('VRFCoordinatorV2Mock');
    coordinator = await VRFCoordinatorFactory.deploy(utils.parseEther('0.1'), 1e9);

    const DexTokenFactory = await ethers.getContractFactory('DexToken');
    const Mock721NFTFactory = await ethers.getContractFactory('Mock721NFT');
    dexToken = await DexTokenFactory.deploy();
    nft = await Mock721NFTFactory.deploy();

    const AuctionLiquidPoolManagerFactory = await ethers.getContractFactory(
      'AuctionLiquidPoolManager',
    );
    const manager = await upgrades.deployProxy(AuctionLiquidPoolManagerFactory, [
      coordinator.address,
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
      [0],
      [1000],
    ];
    const tx = await manager.createPool(params);
    const receipt = await tx.wait();
    pool = await AuctionLiquidPool721Factory.attach(
      receipt.events[receipt.events.length - 1].args.pool_,
    );
    mappingToken = await MappingTokenFactory.attach(await pool.mappingToken());
    await mappingToken.mint(owner.address, utils.parseEther('100'));
    await mappingToken.mint(alice.address, utils.parseEther('100'));
    await mappingToken.mint(bob.address, utils.parseEther('100'));
    await mappingToken.connect(owner).approve(pool.address, utils.parseEther('100'));
    await mappingToken.connect(alice).approve(pool.address, utils.parseEther('100'));
    await mappingToken.connect(bob).approve(pool.address, utils.parseEther('100'));
    await dexToken.mint(alice.address, utils.parseEther('100'));
    await dexToken.mint(bob.address, utils.parseEther('100'));
    await dexToken.connect(owner).approve(pool.address, utils.parseEther('1'));
    await dexToken.connect(alice).approve(pool.address, utils.parseEther('1'));
    await dexToken.connect(bob).approve(pool.address, utils.parseEther('1'));
    await nft.setApprovalForAll(pool.address, true);

    await pool.startAuction(0);
  });

  it('#auction', async () => {
    await pool.connect(alice).bid(0);
    let auction = await pool.auctions(0);
    expect(auction[0]).to.eq(alice.address);
    await pool.connect(bob).bid(0);
    auction = await pool.auctions(0);
    expect(auction[0]).to.eq(bob.address);
    await increaseTime(BigNumber.from('86400'));
    await pool.connect(bob).endAuction(0);
    expect(await nft.ownerOf(0)).to.eq(bob.address);
    expect(await dexToken.balanceOf(pool.address)).to.eq(auction[1]);
  });

  it('#redeem', async () => {
    const tx = await pool.connect(alice).redeem(1);
    const receipt = await tx.wait();
    const requestId = receipt.events[receipt.events.length - 1].args.requestId;
    const beforeOwnerBal = await mappingToken.balanceOf(owner.address);
    const beforeAliceBal = await mappingToken.balanceOf(alice.address);
    await coordinator.fundSubscription(await pool.s_subscriptionId(), utils.parseEther('100'));
    await coordinator.fulfillRandomWordsWithOverride(requestId, pool.address, [123456]);
    expect(await nft.ownerOf(2)).to.eq(alice.address);
    expect(beforeAliceBal.sub(await mappingToken.balanceOf(alice.address))).to.eq(
      utils.parseEther('2'),
    );
    expect((await mappingToken.balanceOf(owner.address)).sub(beforeOwnerBal)).to.eq(
      utils.parseEther('2').div(20),
    );
  });

  it('#swap', async () => {
    await nft.transferFrom(owner.address, alice.address, 3);
    await nft.connect(alice).setApprovalForAll(pool.address, true);
    const tx = await pool.connect(alice).swap(3);
    const receipt = await tx.wait();
    const requestId = receipt.events[receipt.events.length - 1].args.requestId;
    const beforeOwnerBal = await mappingToken.balanceOf(owner.address);
    const beforeAliceBal = await mappingToken.balanceOf(alice.address);
    await coordinator.fundSubscription(await pool.s_subscriptionId(), utils.parseEther('100'));
    await coordinator.fulfillRandomWordsWithOverride(requestId, pool.address, [123456]);
    expect(await nft.ownerOf(3)).to.eq(pool.address);
    expect(await nft.ownerOf(2)).to.eq(alice.address);
    expect(beforeAliceBal.sub(await mappingToken.balanceOf(alice.address))).to.eq(
      utils.parseEther('2'),
    );
    expect((await mappingToken.balanceOf(owner.address)).sub(beforeOwnerBal)).to.eq(
      utils.parseEther('2').div(20),
    );
  });
});
