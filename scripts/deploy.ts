const { ethers, upgrades } = require('hardhat');

async function main() {
  const maNFTFactory = await ethers.getContractFactory('maNFT');
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const Pool721Factory = await ethers.getContractFactory('AuctionLiquidPool721');
  const Pool1155Factory = await ethers.getContractFactory('AuctionLiquidPool1155');

  const maNFT = await maNFTFactory.deploy();
  const manager = await ManagerFactory.attach('0x0Cea6C71323De6426315Fd18B015c9a4E44DFd76');
  const pool721 = await Pool721Factory.deploy(
    '0x2bce784e69d2Ff36c71edcB9F88358dB0DfB55b4',
    '0x326C977E6efc84E512bB9C30f76E30c160eD06FB',
  );
  const pool1155 = await Pool1155Factory.deploy(
    '0x2bce784e69d2Ff36c71edcB9F88358dB0DfB55b4',
    '0x326C977E6efc84E512bB9C30f76E30c160eD06FB',
  );
  await pool721.deployed();
  await pool1155.deployed();
  await manager.setPool721Template(pool721.address);
  await manager.setPool1155Template(pool1155.address);
  console.log(maNFT.address);
  console.log(manager.address);
  console.log(pool721.address);
  console.log(pool1155.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
