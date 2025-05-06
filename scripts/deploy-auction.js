const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");
require('dotenv').config();

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

  const contractArtifact = await hre.artifacts.readArtifact(contractName);

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

async function deployWithTimeout(contractFactory, args, overrides, timeoutMs = 120000) {
  console.log(`Attempting to deploy with ${timeoutMs/1000}s timeout...`);
  console.log(`Constructor arguments:`, args);
  
  // Create a promise that rejects after the timeout
  const timeoutPromise = new Promise((_, reject) => {
    setTimeout(() => reject(new Error(`Deployment timed out after ${timeoutMs/1000} seconds`)), timeoutMs);
  });
  
  // Create the deployment promise
  const deployPromise = args.length > 0 
    ? contractFactory.deploy(...args, overrides) 
    : contractFactory.deploy(overrides);
  
  try {
    // Race the deployment against the timeout
    const contract = await Promise.race([deployPromise, timeoutPromise]);
    console.log("Contract deployment transaction sent, waiting for confirmation...");
    
    // Wait for deployment with a separate timeout
    const deployedContract = await contract.waitForDeployment();
    console.log("Contract deployment confirmed!");
    return deployedContract;
  } catch (error) {
    console.error("Deployment error:", error.message);
    throw error;
  }
}

async function main() {
  // Use custom RPC URL from .env file
  const rpcUrl = process.env.RPC_URL;
  if (!rpcUrl) {
    console.error("RPC_URL not found in .env file");
    process.exit(1);
  }
  
  console.log(`Using custom RPC URL: ${rpcUrl}`);
  
  // Create a new provider with the custom RPC URL
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  
  // Create a wallet with the private key and provider
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error("PRIVATE_KEY not found in .env file");
    process.exit(1);
  }
  
  const wallet = new ethers.Wallet(privateKey, provider);
  console.log(`Using wallet address: ${wallet.address}`);
  
  // Check account balance
  const balance = await provider.getBalance(wallet.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} ETH`);
  
  if (balance < ethers.parseEther("0.01")) {
    console.error("Warning: Account balance is low");
  }
  
  // Get current fee data and increase by 20%
  const feeData = await provider.getFeeData();
  const gasPrice = feeData.gasPrice ? feeData.gasPrice * BigInt(120) / BigInt(100) : undefined;
  
  // Create overrides object with increased gas price and explicit gas limit
  const overrides = {
    gasLimit: 7500000 // Increased from 5000000 to 7500000
  };
  if (gasPrice) {
    overrides.gasPrice = gasPrice;
  }
  
  console.log("Using fee overrides:", {
    gasPrice: gasPrice ? ethers.formatUnits(gasPrice, "gwei") + " gwei" : "not set",
    gasLimit: overrides.gasLimit
  });
  
  // Create a new hardhat ethers instance with our custom provider
  const customHre = { ...hre };
  customHre.ethers = {
    ...hre.ethers,
    provider,
    getSigner: () => wallet,
    getSigners: async () => [wallet]
  };
  
  try {
    // 1. Deploy AuctionItemERC721Factory first
    console.log("Deploying AuctionItemERC721Factory...");
    const AuctionItemERC721Factory = await customHre.ethers.getContractFactory("AuctionItemERC721Factory", wallet);
    
    // Check the ABI to see what constructor arguments are expected
    const factoryAbi = AuctionItemERC721Factory.interface.fragments.find(f => f.type === 'constructor');
    console.log("Factory constructor:", factoryAbi ? factoryAbi.inputs.length + " arguments expected" : "No constructor found");
    
    const auctionItemFactory = await deployWithTimeout(AuctionItemERC721Factory, [], overrides);
    const auctionItemFactoryAddress = await auctionItemFactory.getAddress();
    console.log(`AuctionItemERC721Factory deployed to: ${auctionItemFactoryAddress}`);
    
    // Save deployment info
    await saveDeploymentInfo("AuctionItemERC721Factory", auctionItemFactoryAddress, []);
    
    // 2. Use existing AffiliateEscrowFactory instead of deploying a new one
    console.log("Using existing AffiliateEscrowFactory...");
    const escrowFactoryAddress = "0xE07c41Bc76A8B56ad7E996cF60A3dDeD96ca575D";
    console.log(`AffiliateEscrowFactory address: ${escrowFactoryAddress}`);
    
    // 3. Deploy AuctionHouseFactory
    console.log("Deploying AuctionHouseFactory...");
    const AuctionHouseFactory = await customHre.ethers.getContractFactory("AuctionHouseFactory", wallet);

    // Check the ABI to see what constructor arguments are expected
    const auctionHouseFactoryAbi = AuctionHouseFactory.interface.fragments.find(f => f.type === 'constructor');
    console.log("AuctionHouseFactory constructor:", auctionHouseFactoryAbi ? auctionHouseFactoryAbi.inputs.length + " arguments expected" : "No constructor found");
    if (auctionHouseFactoryAbi) {
      console.log("Expected argument types:", auctionHouseFactoryAbi.inputs.map(i => i.type).join(', '));
      console.log("Expected argument names:", auctionHouseFactoryAbi.inputs.map(i => i.name).join(', '));
    }

    // Deploy the factory with NO arguments
    const auctionHouseFactory = await deployWithTimeout(
      AuctionHouseFactory,
      [], // Empty array - no constructor arguments
      overrides
    );
    const auctionHouseFactoryAddress = await auctionHouseFactory.getAddress();
    console.log(`AuctionHouseFactory deployed to: ${auctionHouseFactoryAddress}`);

    // Save deployment info
    await saveDeploymentInfo("AuctionHouseFactory", auctionHouseFactoryAddress, []);

    // 4. Create an AuctionHouse using the factory
    console.log("Creating AuctionHouse using factory...");
    const auctionHouseName = "Main Auction House";
    const auctionHouseImage = "https://example.com/auction-house-image.png";
    const auctionHouseDescription = "The primary auction house for NFT sales";
    const customDeadline = 21 * 24 * 60 * 60; // 21 days settlement deadline
    const contractURI = "https://example.com/auction-house-metadata";
    const symbol = "AH";

    const createAuctionHouseTx = await auctionHouseFactory.createAuctionHouse(
      auctionHouseName,
      auctionHouseImage,
      auctionHouseDescription,
      contractURI,
      symbol,
      customDeadline,
      auctionItemFactoryAddress,
      escrowFactoryAddress,
      overrides
    );

    console.log("Transaction sent, waiting for confirmation...");
    const receipt = await createAuctionHouseTx.wait();

    // Get the AuctionHouse address from the event
    let auctionHouseAddress;
    for (const log of receipt.logs) {
      try {
        const parsedLog = auctionHouseFactory.interface.parseLog({
          topics: log.topics,
          data: log.data
        });
        if (parsedLog && parsedLog.name === "AuctionHouseCreated") {
          auctionHouseAddress = parsedLog.args[0];
          break;
        }
      } catch (e) {
        continue;
      }
    }

    if (!auctionHouseAddress) {
      console.error("Failed to get AuctionHouse address from event logs");
      process.exit(1);
    }

    console.log(`AuctionHouse created at: ${auctionHouseAddress}`);

    // Save deployment info with constructor arguments for verification
    const auctionHouseConstructorArgs = [
      auctionHouseName,
      auctionHouseImage,
      auctionHouseDescription,
      contractURI,
      symbol,
      customDeadline,
      auctionItemFactoryAddress,
      escrowFactoryAddress
    ];
    await saveDeploymentInfo("AuctionHouse", auctionHouseAddress, auctionHouseConstructorArgs);

    // Get the AuctionHouse contract instance
    const AuctionHouse = await customHre.ethers.getContractFactory("AuctionHouse", wallet);
    const auctionHouse = AuctionHouse.attach(auctionHouseAddress);
    
    // 5. Create an NFT contract through the auction house
    console.log("Creating an NFT contract through the auction house...");
    
    const createNFTTx = await auctionHouse.createNFTContract(
      "Auction Items",
      "AITM",
      "https://example.com/auction-items-metadata",
      overrides
    );
    const createNFTReceipt = await createNFTTx.wait();
    
    // Get the NFT contract address from the event
    let nftContractAddress;
    for (const log of createNFTReceipt.logs) {
      try {
        // Check if the log has a fragment property (indicating it's a parsed event)
        if (log.fragment && log.fragment.name === "NFTContractCreated") {
          nftContractAddress = log.args.nftContract;
          break;
        }
      } catch (e) {
        continue;
      }
    }
    
    if (!nftContractAddress) {
      console.log("Could not find NFTContractCreated event. Trying alternative methods...");
      try {
        // Try to get it from the mapping if event parsing failed
        const nftSymbol = "AITM";
        nftContractAddress = await auctionHouse.nftContracts(nftSymbol);
        console.log(`Retrieved NFT contract address from mapping: ${nftContractAddress}`);
      } catch (error) {
        console.error("Failed to get NFT contract address:", error);
      }
    }
    
    console.log(`NFT contract created at: ${nftContractAddress}`);
    
    // Optional: Deploy AffiliateVerifier if needed for ERC1155 storefront
    console.log("Deploying AffiliateVerifier...");
    const AffiliateVerifier = await customHre.ethers.getContractFactory("AffiliateVerifier", wallet);
    
    // Check the ABI to see what constructor arguments are expected
    const verifierAbi = AffiliateVerifier.interface.fragments.find(f => f.type === 'constructor');
    console.log("Verifier constructor:", verifierAbi ? verifierAbi.inputs.length + " arguments expected" : "No constructor found");
    
    const affiliateVerifier = await deployWithTimeout(AffiliateVerifier, [], overrides);
    const affiliateVerifierAddress = await affiliateVerifier.getAddress();
    console.log(`AffiliateVerifier deployed to: ${affiliateVerifierAddress}`);
    
    // Save deployment info
    await saveDeploymentInfo("AffiliateVerifier", affiliateVerifierAddress, []);
    
    // Summary of deployed contracts
    console.log("\n=== Deployment Summary ===");
    console.log(`AuctionItemERC721Factory: ${auctionItemFactoryAddress}`);
    console.log(`AffiliateEscrowFactory: ${escrowFactoryAddress}`);
    console.log(`AuctionHouseFactory: ${auctionHouseFactoryAddress}`);
    console.log(`AuctionHouse: ${auctionHouseAddress}`);
    console.log(`NFT contract: ${nftContractAddress}`);
    console.log(`AffiliateVerifier: ${affiliateVerifierAddress}`);
    console.log("Deployment completed successfully!");
    
    // Save deployment summary
    const deploymentSummary = {
      auctionItemERC721Factory: auctionItemFactoryAddress,
      affiliateEscrowFactory: escrowFactoryAddress,
      auctionHouseFactory: auctionHouseFactoryAddress,
      auctionHouse: auctionHouseAddress,
      nftContract: nftContractAddress,
      affiliateVerifier: affiliateVerifierAddress
    };

    fs.writeFileSync(
      path.join(__dirname, "../deployments/auction-deployment-summary.json"),
      JSON.stringify(deploymentSummary, null, 2)
    );
    
    console.log("Deployment summary saved to deployments/auction-deployment-summary.json");
    
    // Verify contracts on Etherscan/Basescan
    console.log("\n=== Verifying Contracts ===");
    
    // Verify AuctionItemERC721Factory
    console.log("Verifying AuctionItemERC721Factory...");
    await verifyContract(auctionItemFactoryAddress, []);
    
    // Verify AuctionHouseFactory
    console.log("Verifying AuctionHouseFactory...");
    await verifyContract(auctionHouseFactoryAddress, []);
    
    // Verify AuctionHouse with detailed error handling
    console.log("Verifying AuctionHouse...");
    try {
      await verifyContract(auctionHouseAddress, auctionHouseConstructorArgs);
    } catch (error) {
      console.log("Standard verification failed, trying to check if it's a proxy...");
      
      // Try to get the implementation address using the EIP-1967 storage slot
      const implementationSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
      const implementationData = await provider.getStorageAt(auctionHouseAddress, implementationSlot);
      
      // Convert the data to an address (remove leading zeros and add 0x prefix)
      const implementationAddress = "0x" + implementationData.slice(26);
      
      console.log(`Implementation address: ${implementationAddress}`);
      
      // Verify the implementation - note that the implementation might not need constructor args
      console.log("Verifying implementation contract...");
      await verifyContract(implementationAddress, []);
      
      console.log("Note: The proxy contract itself may not be verifiable through this method.");
      console.log("However, the implementation contract should now be verified.");
    }
    
    // Verify AffiliateVerifier
    console.log("Verifying AffiliateVerifier...");
    await verifyContract(affiliateVerifierAddress, []);
    
    // Try to verify the NFT contract if we have its address
    if (nftContractAddress && nftContractAddress !== ethers.ZeroAddress) {
      console.log("Verifying NFT contract...");
      try {
        // The NFT contract constructor takes 3 arguments: name, symbol, contractURI
        await verifyContract(nftContractAddress, [
          "Auction Items", 
          "AITM", 
          "https://example.com/auction-items-metadata"
        ]);
      } catch (error) {
        console.error("Error verifying NFT contract:", error);
      }
    }
    
    console.log("Contract verification completed!");
  } catch (error) {
    console.error("Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 