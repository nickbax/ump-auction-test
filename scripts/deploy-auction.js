const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function verifyContract(address, constructorArguments) {
  try {
    console.log(
      `Waiting 12 seconds before verifying contract at ${address}...`,
    );
    await sleep(12000);
    await hre.run("verify:verify", {
      address: address,
      constructorArguments: constructorArguments,
    });
    console.log(`Contract at ${address} verified successfully.`);
  } catch (error) {
    if (error.message.includes("already verified")) {
      console.log(`Contract at ${address} is already verified.`);
    } else {
      console.error(`Error verifying contract at ${address}:`, error);
    }
  }
}

async function saveDeploymentInfo(contractName, address, constructorArgs) {
  const deploymentDir = path.join(__dirname, "../deployments");

  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir);
  }

  const deploymentPath = path.join(
    deploymentDir,
    `${contractName}-deployment.json`,
  );

  if (fs.existsSync(deploymentPath)) {
    console.log(`Removing existing file: ${deploymentPath}`);
    fs.unlinkSync(deploymentPath);
  }

  const contractArtifact = artifacts.readArtifactSync(contractName);

  const deploymentInfo = {
    contractName,
    address,
    constructorArguments: constructorArgs,
    deploymentTime: new Date().toISOString(),
    network: hre.network.name,
    chainId: hre.network.config.chainId,
    abi: contractArtifact.abi,
  };

  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`Saved deployment info and ABI for ${contractName}`);
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy AffiliateEscrowFactory (needed for AuctionHouse)
  console.log("Deploying AffiliateEscrowFactory...");
  const AffiliateEscrowFactory = await hre.ethers.getContractFactory(
    "AffiliateEscrowFactory",
  );
  const affiliateEscrowFactory = await AffiliateEscrowFactory.deploy();
  await affiliateEscrowFactory.waitForDeployment();
  const affiliateEscrowFactoryAddress =
    await affiliateEscrowFactory.getAddress();
  console.log(
    "AffiliateEscrowFactory deployed to:",
    affiliateEscrowFactoryAddress,
  );

  // Get the escrow implementation address
  const escrowImplementationAddress =
    await affiliateEscrowFactory.escrowImplementation();
  console.log(
    "Affiliate Escrow implementation deployed to:",
    escrowImplementationAddress,
  );

  // Deploy AuctionItemERC721Factory
  console.log("Deploying AuctionItemERC721Factory...");
  const AuctionItemERC721Factory = await hre.ethers.getContractFactory(
    "AuctionItemERC721Factory",
  );
  const auctionItemERC721Factory = await AuctionItemERC721Factory.deploy();
  await auctionItemERC721Factory.waitForDeployment();
  const auctionItemERC721FactoryAddress = await auctionItemERC721Factory.getAddress();
  console.log(
    "AuctionItemERC721Factory deployed to:",
    auctionItemERC721FactoryAddress,
  );

  // Create an AuctionItemERC721 token
  console.log("Creating an AuctionItemERC721 token...");
  const contractURI = JSON.stringify({
    name: "Auction Item Collection",
    description: "A collection of auction items",
    image: "https://example.com/collection-image.png",
    external_link: "https://example.com",
    seller_fee_basis_points: 100,
    fee_recipient: deployer.address,
  });
  
  const createAuctionItemERC721Tx =
    await auctionItemERC721Factory.createAuctionItemERC721(
      "Auction Items",
      "AUCT",
      contractURI
    );
  const createAuctionItemERC721Receipt = await createAuctionItemERC721Tx.wait();

  const auctionItemERC721CreatedEvent = createAuctionItemERC721Receipt.logs.find(
    (log) => log.eventName === "AuctionItemERC721Created",
  );
  const auctionItemERC721Address = auctionItemERC721CreatedEvent.args.tokenAddress;
  console.log("AuctionItemERC721 contract created at:", auctionItemERC721Address);

  // Deploy AuctionHouseFactory
  console.log("Deploying AuctionHouseFactory...");
  
  // First check the constructor parameters by examining the contract
  const AuctionHouseFactoryContract = await hre.ethers.getContractFactory(
    "AuctionHouseFactory",
  );
  
  // Let's use the affiliate escrow factory as the required parameter
  const auctionHouseFactory = await AuctionHouseFactoryContract.deploy(
    affiliateEscrowFactoryAddress
  );
  
  await auctionHouseFactory.waitForDeployment();
  const auctionHouseFactoryAddress = await auctionHouseFactory.getAddress();
  console.log(
    "AuctionHouseFactory deployed to:",
    auctionHouseFactoryAddress,
  );

  // Create an AuctionHouse
  console.log("Creating an AuctionHouse...");
  const auctionHouseName = "Test Auction House";
  const auctionHouseImage = "https://example.com/auction-house-image.png";
  const auctionHouseDescription = "A test auction house for NFTs";
  const settlementDeadline = 30 * 24 * 60 * 60; // 30 days in seconds
  
  const createAuctionHouseTx =
    await auctionHouseFactory.createAuctionHouse(
      auctionHouseName,
      auctionHouseImage,
      auctionHouseDescription,
      settlementDeadline,
      { gasLimit: 6000000 },
    );

  const createAuctionHouseReceipt = await createAuctionHouseTx.wait();
  const auctionHouseCreatedEvent = createAuctionHouseReceipt.logs.find(
    (log) => log.eventName === "AuctionHouseCreated",
  );
  const auctionHouseAddress = auctionHouseCreatedEvent.args.auctionHouse;
  console.log(
    "AuctionHouse created at:",
    auctionHouseAddress,
  );

  // Save all deployment info
  await saveDeploymentInfo(
    "AffiliateEscrowFactory",
    affiliateEscrowFactoryAddress,
    [],
  );
  await saveDeploymentInfo("AffiliateEscrow", escrowImplementationAddress, []);
  await saveDeploymentInfo(
    "AuctionItemERC721Factory",
    auctionItemERC721FactoryAddress,
    [],
  );
  await saveDeploymentInfo("AuctionItemERC721", auctionItemERC721Address, [
    "Auction Items",
    "AUCT",
    contractURI,
  ]);
  await saveDeploymentInfo(
    "AuctionHouseFactory",
    auctionHouseFactoryAddress,
    [affiliateEscrowFactoryAddress],
  );
  await saveDeploymentInfo(
    "AuctionHouse",
    auctionHouseAddress,
    [
      auctionHouseName,
      auctionHouseImage,
      auctionHouseDescription,
      settlementDeadline,
    ],
  );

  // Verify all contracts
  console.log("Verifying contracts...");
  await verifyContract(affiliateEscrowFactoryAddress, []);
  await verifyContract(escrowImplementationAddress, []);
  await verifyContract(auctionItemERC721FactoryAddress, []);
  await verifyContract(auctionItemERC721Address, [
    "Auction Items",
    "AUCT",
    contractURI,
  ]);
  await verifyContract(auctionHouseFactoryAddress, [affiliateEscrowFactoryAddress]);
  await verifyContract(auctionHouseAddress, [
    auctionHouseName,
    auctionHouseImage,
    auctionHouseDescription,
    deployer.address,
    settlementDeadline,
  ]);

  // Save deployment summary
  const deploymentSummary = {
    affiliateEscrowFactory: affiliateEscrowFactoryAddress,
    affiliateEscrowImplementation: escrowImplementationAddress,
    auctionItemERC721Factory: auctionItemERC721FactoryAddress,
    auctionItemERC721: auctionItemERC721Address,
    auctionHouseFactory: auctionHouseFactoryAddress,
    auctionHouse: auctionHouseAddress,
  };

  fs.writeFileSync(
    path.join(__dirname, "../deployments/auction-deployment-summary.json"),
    JSON.stringify(deploymentSummary, null, 2),
  );

  console.log(
    "Deployment summary saved to deployments/auction-deployment-summary.json",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment error:", error);
    process.exit(1);
  }); 