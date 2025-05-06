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

async function main() {
  // Load the deployment summary to get the addresses
  const deploymentSummaryPath = path.join(__dirname, "../deployments/auction-deployment-summary.json");
  
  if (!fs.existsSync(deploymentSummaryPath)) {
    console.error("Deployment summary file not found. Please run deploy-auction.js first.");
    process.exit(1);
  }
  
  const deploymentSummary = JSON.parse(fs.readFileSync(deploymentSummaryPath, 'utf8'));
  const auctionHouseAddress = deploymentSummary.auctionHouse;
  const auctionItemFactoryAddress = deploymentSummary.auctionItemERC721Factory;
  const escrowFactoryAddress = deploymentSummary.affiliateEscrowFactory;
  
  if (!auctionHouseAddress) {
    console.error("AuctionHouse address not found in deployment summary.");
    process.exit(1);
  }
  
  console.log(`Verifying AuctionHouse at ${auctionHouseAddress}...`);
  
  // We need to provide the constructor arguments for the AuctionHouse
  // The error shows it needs 6 parameters: name, image, description, customDeadline, auctionItemFactory, escrowFactory
  
  // These values should match what was used when creating the auction house
  const constructorArgs = [
    "Main Auction House", // name
    "https://example.com/auction-house-image.png", // image
    "The primary auction house for NFT sales", // description
    21 * 24 * 60 * 60, // customDeadline (21 days in seconds)
    auctionItemFactoryAddress, // auctionItemFactory
    escrowFactoryAddress // escrowFactory
  ];
  
  console.log("Using constructor arguments:", constructorArgs);
  
  try {
    // Try to verify with the constructor arguments
    await verifyContract(auctionHouseAddress, constructorArgs);
  } catch (error) {
    console.log("Direct verification failed, trying alternative approaches...");
    
    // Try to get the implementation address using the EIP-1967 storage slot
    const implementationSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    const implementationData = await hre.ethers.provider.getStorageAt(auctionHouseAddress, implementationSlot);
    
    // Convert the data to an address (remove leading zeros and add 0x prefix)
    const implementationAddress = "0x" + implementationData.slice(26);
    
    console.log(`Implementation address: ${implementationAddress}`);
    
    // Verify the implementation - note that the implementation might not need constructor args
    console.log("Verifying implementation contract...");
    await verifyContract(implementationAddress, []);
    
    console.log("Note: The proxy contract itself may not be verifiable through this method.");
    console.log("However, the implementation contract should now be verified.");
  }
  
  console.log("Verification process completed.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });