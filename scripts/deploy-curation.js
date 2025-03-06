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
    await sleep(12000); // Wait for 12 seconds
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

  // Deploy CurationStorefront
  console.log("Deploying CurationStorefront...");
  const CurationStorefront =
    await hre.ethers.getContractFactory("CurationStorefront");
  const curationStorefront = await CurationStorefront.deploy();
  await curationStorefront.waitForDeployment();
  const curationStorefrontAddress = await curationStorefront.getAddress();
  console.log("CurationStorefront deployed to:", curationStorefrontAddress);

  // Save deployment info
  await saveDeploymentInfo("CurationStorefront", curationStorefrontAddress, []);

  // Verify contract
  await verifyContract(curationStorefrontAddress, []);

  // Save deployment summary
  const deploymentSummary = {
    curationStorefront: curationStorefrontAddress,
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
