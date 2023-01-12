const { ethers, upgrades } = require('hardhat');

async function main() {
  const Mock721NFTFactory = await ethers.getContractFactory('Mock721NFT');
  const nft = await Mock721NFTFactory.deploy();
  await nft.deployed();
  console.log('nft:', nft.address);
  await nft.mint(3);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
