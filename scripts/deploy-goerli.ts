const { ethers, upgrades } = require('hardhat');

async function main() {
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const Pool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');

  const manager = await ManagerFactory.attach('0xA42a561C613412BC149D28fC4b1F3aA013Ee2423');
  const pool721 = await Pool721Factory.deploy();
  await manager.setPool721Template(pool721.address);

  console.log('721 template:', pool721.address);
  // console.log('1155 template:', pool1155.address);
  // await manager.setPool1155Template(pool1155.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
