const { ethers, upgrades } = require('hardhat');

async function main() {
  // const DexTokenFactory = await ethers.getContractFactory('DexToken');
  // const MappingTokenFactory = await ethers.getContractFactory('MappingToken');
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const Pool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
  const Pool1155Factory = await ethers.getContractFactory('AuctionLiquidPool1155');

  // const dexToken = await DexTokenFactory.deploy();
  const manager = await upgrades.deployProxy(ManagerFactory, [
    '0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D',
    '0x334E2D204EaF5EF89F0AD7b4DaC167Bf8Fcc752e',
  ]);
  // const mToken = await MappingTokenFactory.deploy();
  const pool721 = await Pool721Factory.deploy();
  const pool1155 = await Pool1155Factory.deploy();

  // console.log('dex token:', dexToken.address);
  // console.log('token:', mToken.address);
  // console.log('manager:', manager.address);
  console.log('721 template:', pool721.address);
  console.log('1155 template:', pool1155.address);

  await manager.setTokenTemplate('0x18d06552B2767FEf0845f712364028c7ba94F19A');
  await manager.setPool721Template(pool721.address);
  await manager.setPool1155Template(pool1155.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
