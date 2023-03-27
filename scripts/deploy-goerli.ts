const { ethers, upgrades } = require('hardhat');

async function main() {
  const MappingTokenFactory = await ethers.getContractFactory('MappingToken');
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const Pool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
  const Pool1155Factory = await ethers.getContractFactory('AuctionLiquidPool1155');

  const manager = await ManagerFactory.attach('0xD94272E7037BAE96D27754D68538beCf3Dfb30D1');
  const mToken = await MappingTokenFactory.deploy();
  const pool721 = await Pool721Factory.deploy();
  const pool1155 = await Pool1155Factory.deploy();
  console.log('manager:', manager.address);
  console.log('token template:', mToken.address);
  console.log('721 template:', pool721.address);
  console.log('1155 template:', pool1155.address);

  await manager.deployed();
  await manager.setTokenTemplate(mToken.address);
  await manager.setPool721Template(pool721.address);
  await manager.setPool1155Template(pool1155.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
