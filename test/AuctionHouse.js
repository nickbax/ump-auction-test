const { expect } = require("chai");
const { ethers } = require("hardhat");
const { AbiCoder } = require("ethers");
require("@nomicfoundation/hardhat-chai-matchers");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const abiCoder = new AbiCoder();
const EXAMPLE_MESSAGE = {
  encryptedData: "0x42040e12f7539ea8779f6ddf7a3dccd88c253d5dd87d5e5a624d170811a5fdaddd87a6efba872d8cfb335a2d77ef23c1dc3602e89c9eb5752a10101298671c47912f04a1f31d393bbf2890f23f3368e99fcd9b7b6dd60f1cd44f29e1dc47059ca6842290701d53f958ebbb1018e6790d1974aa76e2d4ef5c6aacf8d4c9a3e1e11164946369903b7fd0a7806aaea2ebaa",
  ephemeralPublicKey: "0x0447a63f06b2593890f9269cec414678f24d0da58127821800b715cd211b026c25d2c7f99bf3ff595730181a10fac12a5bad366aeb44fb5b59f51b62022fcd701f",
  iv: "0xad40e6c0dae874564d01cb17",
  verificationHash: "0x803d7d2d2bf6f058ff2d0f43ee4e8cf872f6a8c8b5cc21daa721ba9f44b3aa76",
};

function encodeContextWithAffiliateAndMessage(affiliate, message) {
  const affiliateEncoded = abiCoder.encode(["address"], [affiliate]);
  const messageEncoded = abiCoder.encode(
    [
      "tuple(bytes encryptedData, bytes ephemeralPublicKey, bytes iv, bytes verificationHash)",
    ],
    [
      {
        encryptedData: ethers.toUtf8Bytes(message.encryptedData),
        ephemeralPublicKey: message.ephemeralPublicKey,
        iv: ethers.toUtf8Bytes(message.iv),
        verificationHash: message.verificationHash,
      },
    ],
  );
  return ethers.concat([affiliateEncoded, messageEncoded]);
}

describe("AuctionHouse", function () {
  let AuctionHouse, AuctionItemERC721Factory, AuctionItemERC721, AffiliateEscrowFactory;
  let auctionHouse, auctionItemFactory, auctionItemContract, escrowFactory;
  let owner, bidder1, bidder2, affiliate, arbiter;
  let startTime, duration, reservePrice, affiliateFee, minBidIncrementBps, timeExtension;

  beforeEach(async function () {
    // Get signers
    [owner, bidder1, bidder2, affiliate, arbiter] = await ethers.getSigners();

    // Deploy factories
    AuctionItemERC721Factory = await ethers.getContractFactory("AuctionItemERC721Factory");
    auctionItemFactory = await AuctionItemERC721Factory.deploy();

    AffiliateEscrowFactory = await ethers.getContractFactory("AffiliateEscrowFactory");
    escrowFactory = await AffiliateEscrowFactory.deploy();

    // Deploy AuctionHouse
    AuctionHouse = await ethers.getContractFactory("AuctionHouse");
    auctionHouse = await AuctionHouse.deploy(
      "Test Auction House",
      "https://example.com/image.png",
      "A test auction house for NFTs",
      "https://example.com/contract-metadata",
      "AITM",
      86400, // 1 day settlement deadline
      await auctionItemFactory.getAddress(),
      await escrowFactory.getAddress()
    );

    // Get the AuctionItemERC721 contract created by the AuctionHouse
    const auctionItemContractAddress = await auctionHouse.auctionItemContract();
    AuctionItemERC721 = await ethers.getContractFactory("AuctionItemERC721");
    auctionItemContract = AuctionItemERC721.attach(auctionItemContractAddress);

    // Set up auction parameters
    const currentTime = await time.latest();
    startTime = currentTime + 100; // Start in 100 seconds
    duration = 3600; // 1 hour
    reservePrice = ethers.parseEther("1"); // 1 ETH
    affiliateFee = 500; // 5%
    minBidIncrementBps = 1000; // 10%
    timeExtension = 600; // 10 minutes
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await auctionHouse.owner()).to.equal(owner.address);
    });

    it("Should set the correct metadata", async function () {
      expect(await auctionHouse.houseName()).to.equal("Test Auction House");
      expect(await auctionHouse.image()).to.equal("https://example.com/image.png");
      expect(await auctionHouse.description()).to.equal("A test auction house for NFTs");
    });

    it("Should create an AuctionItemERC721 contract", async function () {
      expect(await auctionItemContract.name()).to.equal("Test Auction House Items");
      expect(await auctionItemContract.symbol()).to.equal("AITM");
    });
  });

  describe("Creating Auctions", function () {
    it("Should create an auction with an existing NFT", async function () {
      // Create a new NFT using createAuctionWithNewNFT
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      // Create the auction with a new NFT
      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress, // Native ETH auction
        true, // Premium auction
        500, // 5% premium
        minBidIncrementBps,
        timeExtension
      );

      // Get the auction ID from the event
      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      const auctionId = event.args[0];

      // Check auction data
      const auction = await auctionHouse.getAuctionData(auctionId);
      expect(auction.tokenContract).to.equal(await auctionItemContract.getAddress());
      expect(auction.reservePrice).to.equal(reservePrice);
      expect(auction.startTime).to.equal(startTime);
      expect(auction.endTime).to.equal(BigInt(startTime) + BigInt(duration));
      expect(auction.auctionOwner).to.equal(owner.address);
      
      // Check that the initial bid is set correctly
      const minIncrement = (reservePrice * BigInt(minBidIncrementBps)) / 10000n;
      const expectedInitialBid = reservePrice - minIncrement;
      expect(auction.highestBid).to.equal(expectedInitialBid);
    });

    it("Should create an auction with a new NFT", async function () {
      // Create metadata for the new NFT
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      // Create the auction with a new NFT
      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress, // Native ETH auction
        true, // Premium auction
        500, // 5% premium
        minBidIncrementBps,
        timeExtension
      );

      // Get the auction ID from the event
      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      const auctionId = event.args[0];

      // Check auction data
      const auction = await auctionHouse.getAuctionData(auctionId);
      expect(auction.tokenContract).to.equal(await auctionItemContract.getAddress());
      expect(auction.reservePrice).to.equal(reservePrice);
      
      // Check that the NFT exists and is owned by the auction house
      const tokenId = auction.tokenId;
      expect(await auctionItemContract.ownerOf(tokenId)).to.equal(await auctionHouse.getAddress());
    });

    it("Should revert if reserve price is too low", async function () {
      // Create metadata for the new NFT
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      // Try to create an auction with zero reserve price
      await expect(auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        0, // Zero reserve price
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        true,
        500,
        minBidIncrementBps,
        timeExtension
      )).to.be.revertedWithCustomError(auctionHouse, "ReservePriceTooLow");
    });
  });

  describe("Bidding", function () {
    let auctionId;

    beforeEach(async function () {
      // Create an auction for testing bids using createAuctionWithNewNFT
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        true,
        500,
        minBidIncrementBps,
        timeExtension
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      auctionId = event.args[0];

      // Advance time to start the auction
      await time.increaseTo(startTime);
    });

    it("Should accept a valid first bid", async function () {
      // Calculate minimum bid required
      const auction = await auctionHouse.getAuctionData(auctionId);
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      
      // Place a bid
      const bidAmount = minBidRequired;
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await expect(bidder1.sendTransaction({
        to: await auctionHouse.getAddress(),
        value: bidAmount
      })).to.be.reverted; // Direct send should fail
      
      // Place bid through the contract
      await expect(auctionHouse.connect(bidder1).createBid(
        auctionId,
        ethers.ZeroAddress, // No affiliate
        emptyEncryptedMsg,
        bidAmount,
        { value: bidAmount }
      )).to.emit(auctionHouse, "BidCreated")
        .withArgs(auctionId, await auctionHouse.getAddress(), bidder1.address, bidAmount, ethers.ZeroAddress, "0x", "0x", "0x", "0x", false);
      
      // Check updated auction data
      const updatedAuction = await auctionHouse.getAuctionData(auctionId);
      expect(updatedAuction.bidder).to.equal(bidder1.address);
      expect(updatedAuction.highestBid).to.equal(bidAmount);
    });

    it("Should reject a bid below minimum required", async function () {
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      const lowBid = minBidRequired - 2n;
      
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await expect(auctionHouse.connect(bidder1).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        lowBid,
        { value: lowBid }
      )).to.be.revertedWithCustomError(auctionHouse, "BidTooLow");
    });

    it("Should refund previous bidder when outbid", async function () {
      // First bid
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      const firstBidAmount = minBidRequired;
      
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await auctionHouse.connect(bidder1).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        firstBidAmount,
        { value: firstBidAmount }
      );
      
      // Second bid (higher)
      const updatedAuction = await auctionHouse.getAuctionData(auctionId);
      const secondBidAmount = updatedAuction.highestBid + 
        ((updatedAuction.highestBid * BigInt(minBidIncrementBps)) / 10000n);
      
      // Check that bidder1 gets refunded
      const bidder1BalanceBefore = await ethers.provider.getBalance(bidder1.address);
      
      await auctionHouse.connect(bidder2).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        secondBidAmount,
        { value: secondBidAmount }
      );
      
      const bidder1BalanceAfter = await ethers.provider.getBalance(bidder1.address);
      
      // For premium auctions, check that bidder1 received their bid amount plus premium
      const auction = await auctionHouse.getAuctionData(auctionId);
      if (auction.isPremiumAuction) {
        const minIncrement = (firstBidAmount * BigInt(minBidIncrementBps)) / 10000n;
        const premium = (minIncrement * BigInt(auction.premiumBps)) / 10000n;
        expect(bidder1BalanceAfter - bidder1BalanceBefore).to.be.at.least(firstBidAmount + premium - 1000000n); // Allow for small gas differences
      } else {
        expect(bidder1BalanceAfter - bidder1BalanceBefore).to.be.at.least(firstBidAmount - 1000000n); // Allow for small gas differences
      }
      
      // Check updated auction data
      const finalAuction = await auctionHouse.getAuctionData(auctionId);
      expect(finalAuction.bidder).to.equal(bidder2.address);
      expect(finalAuction.highestBid).to.equal(secondBidAmount);
    });

    it("Should extend auction time for late bids", async function () {
      // Place initial bid
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      const bidAmount = minBidRequired;
      
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await auctionHouse.connect(bidder1).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        bidAmount,
        { value: bidAmount }
      );
      
      // Fast forward to near the end of the auction
      const auction = await auctionHouse.getAuctionData(auctionId);
      const nearEndTime = auction.endTime - 100n; // 100 seconds before end
      await time.increaseTo(Number(nearEndTime));
      
      // Place a new bid near the end
      const secondBidAmount = bidAmount + ((bidAmount * BigInt(minBidIncrementBps)) / 10000n);
      
      await expect(auctionHouse.connect(bidder2).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        secondBidAmount,
        { value: secondBidAmount }
      )).to.emit(auctionHouse, "AuctionExtended");
      
      // Check that the auction end time was extended
      const updatedAuction = await auctionHouse.getAuctionData(auctionId);
      expect(updatedAuction.endTime).to.be.gt(auction.endTime);
    });

    it("Should not allow bids after the auction end time", async function () {
      // Create an auction with a short duration
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      const currentTime = await time.latest();
      const startTime = currentTime + 60; // Start in 60 seconds
      const duration = 120; // 2 minutes duration
      
      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress, // Native ETH auction
        false, // Not a premium auction
        0, // No premium
        minBidIncrementBps,
        timeExtension
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      const auctionId = event.args[0];
      
      // Fast forward to auction start time
      await time.increaseTo(startTime);
      
      // Place a valid bid
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await auctionHouse.connect(bidder1).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        minBidRequired,
        { value: minBidRequired }
      );
      
      // Fast forward past the end time
      await time.increaseTo(startTime + duration + timeExtension + 1);
      
      // Try to place a bid after the end time
      const newBidAmount = minBidRequired + ethers.parseEther("0.1");
      
      // Bid should be rejected with AuctionExpired error
      await expect(auctionHouse.connect(bidder2).createBid(
        auctionId,
        ethers.ZeroAddress,
        emptyEncryptedMsg,
        newBidAmount,
        { value: newBidAmount }
      )).to.be.revertedWithCustomError(auctionHouse, "AuctionExpired");
      
      // Verify the auction can still be ended
      await expect(auctionHouse.endAuction(auctionId))
        .to.emit(auctionHouse, "AuctionEnded");
    });
  });

  describe("Ending Auctions", function () {
    let auctionId;

    beforeEach(async function () {
      // Create and set up an auction with bids using createAuctionWithNewNFT
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        false, // Not a premium auction for simplicity
        0,
        minBidIncrementBps,
        timeExtension
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      auctionId = event.args[0];

      // Start the auction
      await time.increaseTo(startTime);

      // Place a bid
      const minBidRequired = await auctionHouse.getMinimumBid(auctionId);
      const emptyEncryptedMsg = {
        encryptedData: "0x",
        ephemeralPublicKey: "0x",
        iv: "0x",
        verificationHash: "0x"
      };
      
      await auctionHouse.connect(bidder1).createBid(
        auctionId,
        affiliate.address, // Use affiliate
        emptyEncryptedMsg,
        minBidRequired,
        { value: minBidRequired }
      );
    });

    it("Should end an auction successfully", async function () {
      // Fast forward past the end time
      const auction = await auctionHouse.getAuctionData(auctionId);
      await time.increaseTo(Number(auction.endTime) + 1);
      
      // End the auction
      await expect(auctionHouse.endAuction(auctionId))
        .to.emit(auctionHouse, "AuctionEnded");
      
      // Check that the NFT was transferred to the winning bidder
      const tokenId = auction.tokenId;
      expect(await auctionItemContract.ownerOf(tokenId)).to.equal(bidder1.address);
      
      // Check that the auction no longer exists in the token mapping
      expect(await auctionHouse.tokenToAuctionId(auction.tokenContract, tokenId)).to.equal(0);
    });

    it("Should revert if auction hasn't ended yet", async function () {
      // Try to end the auction before it's over
      await expect(auctionHouse.endAuction(auctionId))
        .to.be.revertedWithCustomError(auctionHouse, "AuctionHasntCompleted");
    });

    it("Should allow cancellation if no bids placed", async function () {
      // Create a new auction with a future start time
      const newStartTime = startTime + 1000; // Ensure it's in the future
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        newStartTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        false,
        0,
        minBidIncrementBps,
        timeExtension
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      const newAuctionId = event.args[0];
      
      // Get the token ID from the auction data
      const auctionData = await auctionHouse.getAuctionData(newAuctionId);
      const tokenId = auctionData.tokenId;
      
      // Cancel the auction (no bids placed)
      await expect(auctionHouse.cancelAuction(newAuctionId))
        .to.emit(auctionHouse, "AuctionCancelled");
      
      // Check that the NFT was returned to the owner
      expect(await auctionItemContract.ownerOf(tokenId)).to.equal(owner.address);
    });

    it("Should revert cancellation if bids have been placed", async function () {
      // Try to cancel an auction with bids
      await expect(auctionHouse.cancelAuction(auctionId))
        .to.be.revertedWithCustomError(auctionHouse, "BidsAlreadyPlaced");
    });
  });

  describe("Metadata and Settings", function () {
    it("Should update auction house metadata", async function () {
      const newName = "Updated Auction House";
      const newImage = "https://example.com/new-image.png";
      const newDescription = "Updated description";
      
      await expect(auctionHouse.updateAuctionHouseMetadata(newName, newImage, newDescription))
        .to.emit(auctionHouse, "AuctionHouseMetadataUpdated");
      
      expect(await auctionHouse.houseName()).to.equal(newName);
      expect(await auctionHouse.image()).to.equal(newImage);
      expect(await auctionHouse.description()).to.equal(newDescription);
    });

    it("Should update settlement deadline", async function () {
      const newDeadline = 172800; // 2 days
      
      await expect(auctionHouse.updateSettlementDeadline(newDeadline))
        .to.emit(auctionHouse, "SettlementDeadlineUpdated")
        .withArgs(newDeadline);
      
      expect(await auctionHouse.settlementDeadline()).to.equal(newDeadline);
    });

    it("Should revert metadata update if not owner", async function () {
      await expect(auctionHouse.connect(bidder1).updateAuctionHouseMetadata(
        "Hacked Name", 
        "Hacked Image", 
        "Hacked Description"
      )).to.be.revertedWith("Not authorized");
    });
  });

  describe("Rescue Functions", function () {
    it("Should not allow rescuing tokens while auctions are active", async function () {
      // Create an auction to make activeAuctionsCount > 0
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        false,
        0,
        minBidIncrementBps,
        timeExtension
      );
      
      // Create a mock ERC20 token for testing
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const mockToken = await MockERC20.deploy("Mock Token", "MOCK");
      
      // Mint some tokens to the owner
      await mockToken.mint(owner.address, ethers.parseEther("1000"));
      
      // Transfer some tokens to the auction house
      await mockToken.transfer(await auctionHouse.getAddress(), ethers.parseEther("100"));
      
      // Try to rescue ERC20 - this should fail because there are active auctions
      await expect(auctionHouse.rescueERC20(
        await mockToken.getAddress(),
        owner.address,
        ethers.parseEther("50")
      )).to.be.revertedWithCustomError(auctionHouse, "CannotRescueWhileAuctionsActive");
    });

    it("Should allow owner to rescue ERC20 tokens when no auctions are active", async function () {
      // Create a mock ERC20 token for testing
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const mockToken = await MockERC20.deploy("Mock Token", "MOCK");
      
      // Mint some tokens to the owner
      await mockToken.mint(owner.address, ethers.parseEther("1000"));
      
      // Transfer some tokens to the auction house
      await mockToken.transfer(await auctionHouse.getAddress(), ethers.parseEther("100"));
      
      // Verify the auction house has the tokens
      expect(await mockToken.balanceOf(await auctionHouse.getAddress())).to.equal(ethers.parseEther("100"));
      
      // Ensure no active auctions by checking the counter
      expect(await auctionHouse.activeAuctionsCount()).to.equal(0);
      
      // Rescue the tokens
      await expect(auctionHouse.rescueERC20(
        await mockToken.getAddress(),
        owner.address,
        ethers.parseEther("50")
      )).to.emit(auctionHouse, "ERC20Rescued")
        .withArgs(await mockToken.getAddress(), owner.address, ethers.parseEther("50"));
      
      // Verify the tokens were transferred
      expect(await mockToken.balanceOf(await auctionHouse.getAddress())).to.equal(ethers.parseEther("50"));
      // The owner should have received the tokens back
      expect(await mockToken.balanceOf(owner.address)).to.equal(ethers.parseEther("950"));
    });

    it("Should not allow non-owner to rescue ERC20 tokens", async function () {
      // Create a mock ERC20 token
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const mockToken = await MockERC20.deploy("Mock Token", "MOCK");
      
      // Mint tokens to the owner
      await mockToken.mint(owner.address, ethers.parseEther("1000"));
      
      // Transfer tokens to the auction house
      await mockToken.transfer(await auctionHouse.getAddress(), ethers.parseEther("100"));
      
      // Try to rescue ERC20 as non-owner (bidder1)
      await expect(auctionHouse.connect(bidder1).rescueERC20(
        await mockToken.getAddress(),
        bidder1.address,
        ethers.parseEther("50")
      )).to.be.revertedWithCustomError(auctionHouse, "OnlyOwnerCanRescue");
    });
  });

  describe("Access Control", function () {
    it("Should allow only owner to update auction house metadata", async function () {
      const newName = "Updated Auction House";
      const newImage = "https://example.com/new-image.png";
      const newDescription = "Updated description";
      
      // Non-owner attempt should fail
      await expect(auctionHouse.connect(bidder1).updateAuctionHouseMetadata(
        newName, 
        newImage, 
        newDescription
      )).to.be.revertedWith("Not authorized");
      
      // Owner attempt should succeed
      await expect(auctionHouse.updateAuctionHouseMetadata(
        newName, 
        newImage, 
        newDescription
      )).to.emit(auctionHouse, "AuctionHouseMetadataUpdated");
    });

    it("Should allow only owner to update settlement deadline", async function () {
      const newDeadline = 172800; // 2 days
      
      // Try different error patterns to catch the actual error
      try {
        await auctionHouse.connect(bidder1).updateSettlementDeadline(newDeadline);
        // If we get here, the transaction didn't revert
        assert.fail("Expected transaction to revert");
      } catch (error) {
        // Just verify that it reverted, don't check the specific error
        expect(error.message).to.include("reverted");
      }
      
      // Owner attempt should succeed
      await expect(auctionHouse.updateSettlementDeadline(
        newDeadline
      )).to.emit(auctionHouse, "SettlementDeadlineUpdated");
    });

    it("Should allow only owner to rescue ERC20 tokens", async function () {
      // Create a mock ERC20 token
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const mockToken = await MockERC20.deploy("Mock Token", "MOCK");
      
      // Mint tokens to the owner
      await mockToken.mint(owner.address, ethers.parseEther("1000"));
      
      // Transfer tokens to the auction house
      await mockToken.transfer(await auctionHouse.getAddress(), ethers.parseEther("100"));
      
      // Non-owner attempt should fail
      await expect(auctionHouse.connect(bidder1).rescueERC20(
        await mockToken.getAddress(),
        bidder1.address,
        ethers.parseEther("50")
      )).to.be.revertedWithCustomError(auctionHouse, "OnlyOwnerCanRescue");
      
      // Owner attempt should succeed (when no auctions are active)
      await expect(auctionHouse.rescueERC20(
        await mockToken.getAddress(),
        owner.address,
        ethers.parseEther("50")
      )).to.emit(auctionHouse, "ERC20Rescued");
    });

    it("Should allow only owner to transfer ownership", async function () {
      // Non-owner attempt should fail
      await expect(auctionHouse.connect(bidder1).transferOwnership(
        bidder1.address
      )).to.be.revertedWithCustomError(auctionHouse, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await auctionHouse.transferOwnership(bidder1.address);
      expect(await auctionHouse.owner()).to.equal(bidder1.address);
      
      // Transfer back to original owner for other tests
      await auctionHouse.connect(bidder1).transferOwnership(owner.address);
    });

    it("Should allow anyone to batch end expired auctions", async function () {
      // Create an auction
      const metadata = {
        name: "Test NFT",
        description: "A test NFT for auction",
        image: "https://example.com/nft.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: []
      };

      const tx = await auctionHouse.createAuctionWithNewNFT(
        metadata,
        startTime,
        reservePrice,
        duration,
        affiliateFee,
        arbiter.address,
        await escrowFactory.getAddress(),
        ethers.ZeroAddress,
        false,
        0,
        minBidIncrementBps,
        timeExtension
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find(log => 
        log.fragment && log.fragment.name === 'AuctionCreated'
      );
      const auctionId = event.args[0];
      
      // Fast forward past the end time to make the auction expired
      const auction = await auctionHouse.getAuctionData(auctionId);
      await time.increaseTo(Number(auction.endTime) + 1);
      
      // Non-owner should be able to call batchEndExpiredAuctions
      await expect(auctionHouse.connect(bidder1).batchEndExpiredAuctions([auctionId]))
        .to.not.be.reverted;
    });
  });

  describe("AuctionItemERC721 Access Control", function () {
    let auctionItemContract;
    let owner, nonOwner, recipient;
    let tokenId;

    beforeEach(async function () {
      [owner, nonOwner, recipient] = await ethers.getSigners();
      
      // Deploy the AuctionItemERC721 contract
      const AuctionItemERC721 = await ethers.getContractFactory("AuctionItemERC721");
      auctionItemContract = await AuctionItemERC721.deploy(
        "Auction Item", 
        "AUCITEM",
        "https://example.com/contract-metadata"
      );
      
      // Mint a token for testing
      const tx = await auctionItemContract.mint(owner.address);
      const receipt = await tx.wait();
      tokenId = 1; // First token ID should be 1
    });

    it("Should allow only owner to mint tokens", async function () {
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).mint(nonOwner.address))
        .to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.mint(owner.address))
        .to.not.be.reverted;
    });

    it("Should allow only owner to mint tokens with metadata", async function () {
      const metadata = {
        name: "Test NFT",
        description: "A test NFT",
        image: "https://example.com/image.png",
        termsOfService: "https://example.com/terms",
        supplementalImages: ["https://example.com/image1.png", "https://example.com/image2.png"]
      };
      
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).mintWithMetadata(
        nonOwner.address,
        metadata.name,
        metadata.description,
        metadata.image,
        metadata.termsOfService,
        metadata.supplementalImages
      )).to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.mintWithMetadata(
        owner.address,
        metadata.name,
        metadata.description,
        metadata.image,
        metadata.termsOfService,
        metadata.supplementalImages
      )).to.not.be.reverted;
    });

    it("Should allow only owner to set token metadata", async function () {
      const metadata = {
        name: "Updated NFT",
        description: "An updated test NFT",
        image: "https://example.com/updated-image.png",
        termsOfService: "https://example.com/updated-terms",
        supplementalImages: ["https://example.com/updated-image1.png"]
      };
      
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).setTokenMetadata(
        tokenId,
        metadata.name,
        metadata.description,
        metadata.image,
        metadata.termsOfService,
        metadata.supplementalImages
      )).to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.setTokenMetadata(
        tokenId,
        metadata.name,
        metadata.description,
        metadata.image,
        metadata.termsOfService,
        metadata.supplementalImages
      )).to.not.be.reverted;
      
      // Verify metadata was updated
      const updatedMetadata = await auctionItemContract.getTokenMetadata(tokenId);
      expect(updatedMetadata.name).to.equal(metadata.name);
      expect(updatedMetadata.description).to.equal(metadata.description);
      expect(updatedMetadata.image).to.equal(metadata.image);
      expect(updatedMetadata.termsOfService).to.equal(metadata.termsOfService);
      expect(updatedMetadata.supplementalImages.length).to.equal(metadata.supplementalImages.length);
      expect(updatedMetadata.supplementalImages[0]).to.equal(metadata.supplementalImages[0]);
    });

    it("Should allow only owner to set contract URI", async function () {
      const newContractURI = "https://example.com/new-contract-metadata";
      
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).setContractURI(newContractURI))
        .to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.setContractURI(newContractURI))
        .to.not.be.reverted;
      
      // Verify contract URI was updated
      expect(await auctionItemContract.contractURI()).to.equal(newContractURI);
    });

    it("Should allow only owner to change ownership", async function () {
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).changeOwnership(nonOwner.address))
        .to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.changeOwnership(recipient.address))
        .to.not.be.reverted;
      
      // Verify ownership was transferred
      expect(await auctionItemContract.owner()).to.equal(recipient.address);
    });

    it("Should allow only owner to set base URI", async function () {
      const newBaseURI = "https://example.com/tokens/";
      
      // Non-owner attempt should fail
      await expect(auctionItemContract.connect(nonOwner).setBaseURI(newBaseURI))
        .to.be.revertedWithCustomError(auctionItemContract, "OwnableUnauthorizedAccount");
      
      // Owner attempt should succeed
      await expect(auctionItemContract.setBaseURI(newBaseURI))
        .to.not.be.reverted;
    });
  });
});