import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { increaseTime } from './utils';

describe('Auction Liquid Pool 721', function () {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let manager: Contract;
  let pool: Contract;
  let maNFT: Contract;
  let nft: Contract;
  let coordinator: Contract;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    const LinkFactory = await ethers.getContractFactory('LinkToken');
    const VRFCoordinatorFactory = await ethers.getContractFactory('VRFCoordinatorMock');
    const link = await LinkFactory.deploy();
    coordinator = await VRFCoordinatorFactory.deploy(link.address);

    const maNFTFactory = await ethers.getContractFactory('maNFT');
    const Mock721NFTFactory = await ethers.getContractFactory('Mock721NFT');
    maNFT = await maNFTFactory.deploy();
    nft = await Mock721NFTFactory.deploy();

    const AuctionLiquidPool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
    const AuctionLiquidPoolManagerFactory = await ethers.getContractFactory(
      'AuctionLiquidPoolManager',
    );
    manager = await AuctionLiquidPoolManagerFactory.deploy(maNFT.address);
    const poolTemplate = await AuctionLiquidPool721Factory.deploy(
      coordinator.address,
      link.address,
    );
    await manager.setPool721Template(poolTemplate.address);

    await nft.mint(4);
    await nft.setApprovalForAll(manager.address, true);

    const params = [
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
    const tx = await manager.createPool721(...params);
    const receipt = await tx.wait();
    pool = await AuctionLiquidPool721Factory.attach(
      receipt.events[receipt.events.length - 1].args.pool_,
    );
    await maNFT.mint(owner.address, utils.parseEther('100'));
    await maNFT.mint(alice.address, utils.parseEther('100'));
    await maNFT.mint(bob.address, utils.parseEther('100'));
    await maNFT.connect(owner).approve(pool.address, utils.parseEther('100'));
    await maNFT.connect(alice).approve(pool.address, utils.parseEther('100'));
    await maNFT.connect(bob).approve(pool.address, utils.parseEther('100'));
    await link.transfer(pool.address, utils.parseEther('1'));
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
    await coordinator.callBackWithRandomness(requestId, '123456', pool.address);
    expect(await nft.ownerOf(2)).to.eq(owner.address);
  });

  it('#swap', async () => {
    const tx = await pool.connect(owner).swap(3);
    const receipt = await tx.wait();
    const requestId = receipt.events[receipt.events.length - 1].args.requestId;
    await coordinator.callBackWithRandomness(requestId, '123456', pool.address);
    expect(await nft.ownerOf(3)).to.eq(pool.address);
    expect(await nft.ownerOf(2)).to.eq(owner.address);
  });
});