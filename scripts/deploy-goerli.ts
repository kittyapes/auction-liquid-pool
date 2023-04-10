const { ethers, upgrades } = require('hardhat');

async function main() {
  const MappingTokenFactory = await ethers.getContractFactory('MappingToken');
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const Pool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
  const Pool1155Factory = await ethers.getContractFactory('AuctionLiquidPool1155');

  const manager = await upgrades.deployProxy(ManagerFactory, [
    '0x334E2D204EaF5EF89F0AD7b4DaC167Bf8Fcc752e',
  ]);
  // const mToken = await MappingTokenFactory.deploy();
  const pool721 = await Pool721Factory.deploy();
  const pool1155 = await Pool1155Factory.deploy();
  console.log('manager:', manager.address);
  // console.log('token template:', mToken.address);
  console.log('721 template:', pool721.address);
  console.log('1155 template:', pool1155.address);

  await manager.deployed();
  await manager.setTokenTemplate('0xa8ebf0daef4B62a2b21495d32598F3d31AbF147E');
  await manager.setPool721Template(pool721.address);
  await manager.setPool1155Template(pool1155.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
