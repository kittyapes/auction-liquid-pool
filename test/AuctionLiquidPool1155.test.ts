import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { BigNumber, constants, Contract, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { increaseTime } from './utils';

describe('Auction Liquid Pool 1155', function () {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let dexToken: Contract;
  let mappingToken: Contract;
  let nft: Contract;
  let pool: Contract;

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    const DexTokenFactory = await ethers.getContractFactory('DexToken');
    const Mock1155NFTFactory = await ethers.getContractFactory('Mock1155NFT');
    dexToken = await DexTokenFactory.deploy();
    nft = await Mock1155NFTFactory.deploy();

    const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
    const manager = await upgrades.deployProxy(ManagerFactory, [dexToken.address]);

    const MappingTokenFactory = await ethers.getContractFactory('MappingToken');
    const AuctionLiquidPool1155Factory = await ethers.getContractFactory('AuctionLiquidPool1155');
    const mToken = await MappingTokenFactory.deploy();
    const pool1155Template = await AuctionLiquidPool1155Factory.deploy();
    await manager.setTokenTemplate(mToken.address);
    await manager.setPool1155Template(pool1155Template.address);

    await dexToken.transfer(manager.address, utils.parseEther('10000'));
    await nft.batchMint([0, 1, 2], [1, 1, 1]);
    await nft.setApprovalForAll(manager.address, true);

    const params = [
      'HypeX',
      '',
      constants.AddressZero,
      nft.address,
      86400,
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
    pool = await AuctionLiquidPool1155Factory.attach(
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
    await nft.connect(alice).batchMint([3, 4, 5], [1, 1, 1]);
    await nft.connect(alice).setApprovalForAll(pool.address, true);
    await increaseTime(BigNumber.from('86400'));
  });

  it('#auction', async () => {
    await pool.startAuction(0);
    await pool.connect(alice).bid(0);
    let auction = await pool.auctions(0);
    expect(auction[0]).to.eq(alice.address);
    await pool.connect(bob).bid(0);
    auction = await pool.auctions(0);
    expect(auction[0]).to.eq(bob.address);
    await increaseTime(BigNumber.from('86400'));
    await pool.connect(bob).endAuction(0);
    expect(await nft.balanceOf(bob.address, 0)).to.eq(1);
    expect(await dexToken.balanceOf(pool.address)).to.eq(auction[1]);
  });

  it('#redeem', async () => {
    const beforeOwnerBal = await mappingToken.balanceOf(owner.address);
    const beforeAliceBal = await mappingToken.balanceOf(alice.address);
    const tx = await pool.connect(alice).redeem(2);
    const receipt = await tx.wait();
    const tokenIds = receipt.events[receipt.events.length - 1].args.tokenIds;
    expect(await nft.balanceOf(alice.address, tokenIds[0])).to.eq(1);
    expect(await nft.balanceOf(alice.address, tokenIds[1])).to.eq(1);
    expect(beforeAliceBal.sub(await mappingToken.balanceOf(alice.address))).to.eq(
      utils.parseEther('4'),
    );
    expect((await mappingToken.balanceOf(owner.address)).sub(beforeOwnerBal)).to.eq(
      utils.parseEther('4').div(20),
    );
  });

  it('#swap', async () => {
    const tx = await pool.connect(alice).swap(3);
    const receipt = await tx.wait();
    const tokenId = receipt.events[receipt.events.length - 1].args.dstTokenId;
    expect(await nft.balanceOf(pool.address, 3)).to.eq(1);
    expect(await nft.balanceOf(alice.address, tokenId)).to.eq(1);
  });

  it('#lockNFTs', async () => {
    const beforeAliceBal = await mappingToken.balanceOf(alice.address);
    await pool.connect(alice).lockNFTs([3, 4, 5]);
    expect((await mappingToken.balanceOf(alice.address)).sub(beforeAliceBal)).to.eq(
      utils.parseEther('6'),
    );
  });
});
