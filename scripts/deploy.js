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

  // Deploy AffiliateVerifier implementation
  console.log("Deploying AffiliateVerifier implementation...");
  const AffiliateVerifier =
    await hre.ethers.getContractFactory("AffiliateVerifier");
  const affiliateVerifierImplementation = await AffiliateVerifier.deploy();
  await affiliateVerifierImplementation.waitForDeployment();
  console.log(
    "AffiliateVerifier implementation deployed to:",
    await affiliateVerifierImplementation.getAddress(),
  );

  // Deploy AffiliateVerifierProxy
  console.log("Deploying AffiliateVerifierProxy...");
  const initData =
    affiliateVerifierImplementation.interface.encodeFunctionData("initialize");
  const AffiliateVerifierProxy = await hre.ethers.getContractFactory(
    "AffiliateVerifierProxy",
  );
  const affiliateVerifierProxy = await AffiliateVerifierProxy.deploy(
    await affiliateVerifierImplementation.getAddress(),
    initData,
  );
  await affiliateVerifierProxy.waitForDeployment();
  const affiliateVerifierAddress = await affiliateVerifierProxy.getAddress();
  console.log("AffiliateVerifierProxy deployed to:", affiliateVerifierAddress);

  // Deploy AffiliateEscrowFactory
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

  // Deploy ReceiptERC1155Factory
  console.log("Deploying ReceiptERC1155Factory...");
  const ReceiptERC1155Factory = await hre.ethers.getContractFactory(
    "ReceiptERC1155Factory",
  );
  const receiptERC1155Factory = await ReceiptERC1155Factory.deploy();
  await receiptERC1155Factory.waitForDeployment();
  const receiptERC1155FactoryAddress = await receiptERC1155Factory.getAddress();
  console.log(
    "ReceiptERC1155Factory deployed to:",
    receiptERC1155FactoryAddress,
  );

  // Create a ReceiptERC1155 token
  console.log("Creating a ReceiptERC1155 token...");
  const contractURI = JSON.stringify({
    name: "Receipt Collection",
    description: "A collection of transaction receipts",
    image: "https://example.com/collection-image.png",
    external_link: "https://example.com",
    seller_fee_basis_points: 100,
    fee_recipient: deployer.address,
  });
  const createReceiptERC1155Tx =
    await receiptERC1155Factory.createReceiptERC1155(contractURI);
  const createReceiptERC1155Receipt = await createReceiptERC1155Tx.wait();

  const receiptERC1155CreatedEvent = createReceiptERC1155Receipt.logs.find(
    (log) => log.eventName === "ReceiptERC1155Created",
  );
  const receiptERC1155Address = receiptERC1155CreatedEvent.args.tokenAddress;
  console.log("ReceiptERC1155 contract created at:", receiptERC1155Address);

  // Deploy AffiliateERC1155StorefrontFactory
  console.log("Deploying AffiliateERC1155StorefrontFactory...");
  const AffiliateERC1155StorefrontFactory = await hre.ethers.getContractFactory(
    "AffiliateERC1155StorefrontFactory",
  );
  const seaportAddress = "0x0000000000000068F116a894984e2DB1123eB395"; // Seaport v1.6 on Base
  const minSettleTime = 7 * 24 * 60 * 60; // 1 week in seconds

  const affiliateERC1155StorefrontFactory =
    await AffiliateERC1155StorefrontFactory.deploy(
      seaportAddress,
      minSettleTime,
    );
  await affiliateERC1155StorefrontFactory.waitForDeployment();
  const affiliateERC1155StorefrontFactoryAddress =
    await affiliateERC1155StorefrontFactory.getAddress();
  console.log(
    "AffiliateERC1155StorefrontFactory deployed to:",
    affiliateERC1155StorefrontFactoryAddress,
  );

  // Create an AffiliateERC1155Storefront
  console.log("Creating an AffiliateERC1155Storefront...");
  const designatedArbiter = deployer.address;
  const initialSettleDeadline = 3 * 7 * 24 * 60 * 60; // 3 weeks in seconds

  const createStorefrontTx =
    await affiliateERC1155StorefrontFactory.createStorefront(
      designatedArbiter,
      receiptERC1155Address,
      affiliateEscrowFactoryAddress,
      affiliateVerifierAddress,
      initialSettleDeadline,
      { gasLimit: 6000000 },
    );

  const createStorefrontReceipt = await createStorefrontTx.wait();
  const storefrontCreatedEvent = createStorefrontReceipt.logs.find(
    (log) => log.eventName === "StorefrontCreated",
  );
  const affiliateStorefrontAddress = storefrontCreatedEvent.args.storefront;
  console.log(
    "AffiliateERC1155Storefront created at:",
    affiliateStorefrontAddress,
  );

  // Save all deployment info
  await saveDeploymentInfo(
    "AffiliateVerifier",
    await affiliateVerifierImplementation.getAddress(),
    [],
  );
  await saveDeploymentInfo("AffiliateVerifierProxy", affiliateVerifierAddress, [
    await affiliateVerifierImplementation.getAddress(),
    initData,
  ]);
  await saveDeploymentInfo(
    "AffiliateEscrowFactory",
    affiliateEscrowFactoryAddress,
    [],
  );
  await saveDeploymentInfo("AffiliateEscrow", escrowImplementationAddress, []);
  await saveDeploymentInfo(
    "ReceiptERC1155Factory",
    receiptERC1155FactoryAddress,
    [],
  );
  await saveDeploymentInfo("ReceiptERC1155", receiptERC1155Address, [
    contractURI,
  ]);
  await saveDeploymentInfo(
    "AffiliateERC1155StorefrontFactory",
    affiliateERC1155StorefrontFactoryAddress,
    [seaportAddress, minSettleTime],
  );
  await saveDeploymentInfo(
    "AffiliateERC1155Storefront",
    affiliateStorefrontAddress,
    [
      seaportAddress,
      designatedArbiter,
      affiliateEscrowFactoryAddress,
      receiptERC1155Address,
      affiliateVerifierAddress,
      minSettleTime,
      initialSettleDeadline,
    ],
  );

  // Verify all contracts
  console.log("Verifying contracts...");
  await verifyContract(await affiliateVerifierImplementation.getAddress(), []);
  await verifyContract(affiliateVerifierAddress, [
    await affiliateVerifierImplementation.getAddress(),
    initData,
  ]);
  await verifyContract(affiliateEscrowFactoryAddress, []);
  await verifyContract(escrowImplementationAddress, []);
  await verifyContract(receiptERC1155FactoryAddress, []);
  await verifyContract(receiptERC1155Address, [contractURI]);
  await verifyContract(affiliateERC1155StorefrontFactoryAddress, [
    seaportAddress,
    minSettleTime,
  ]);
  await verifyContract(affiliateStorefrontAddress, [
    seaportAddress,
    designatedArbiter,
    affiliateEscrowFactoryAddress,
    receiptERC1155Address,
    affiliateVerifierAddress,
    minSettleTime,
    initialSettleDeadline,
  ]);

  // Save deployment summary
  const deploymentSummary = {
    affiliateVerifierImplementation:
      await affiliateVerifierImplementation.getAddress(),
    affiliateVerifierProxy: affiliateVerifierAddress,
    affiliateEscrowFactory: affiliateEscrowFactoryAddress,
    affiliateEscrowImplementation: escrowImplementationAddress,
    receiptERC1155Factory: receiptERC1155FactoryAddress,
    receiptERC1155: receiptERC1155Address,
    affiliateERC1155StorefrontFactory: affiliateERC1155StorefrontFactoryAddress,
    affiliateERC1155Storefront: affiliateStorefrontAddress,
  };

  fs.writeFileSync(
    path.join(__dirname, "../deployments/deployment-summary.json"),
    JSON.stringify(deploymentSummary, null, 2),
  );

  console.log(
    "Deployment summary saved to deployments/deployment-summary.json",
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment error:", error);
    process.exit(1);
  });
