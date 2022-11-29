const { ethers, upgrades } = require('hardhat');

async function main() {
  const maNFTFactory = await ethers.getContractFactory('maNFT');
  const ManagerFactory = await ethers.getContractFactory('AuctionLiquidPoolManager');
  const PoolFactory = await ethers.getContractFactory('AuctionLiquidPool');

  const maNFT = await maNFTFactory.deploy();
  const manager = await ManagerFactory.deploy(maNFT.address);
  const pool = await PoolFactory.deploy(
    '0x2bce784e69d2Ff36c71edcB9F88358dB0DfB55b4',
    '0x326C977E6efc84E512bB9C30f76E30c160eD06FB',
  );
  console.log(maNFT.address);
  console.log(manager.address);
  console.log(pool.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
