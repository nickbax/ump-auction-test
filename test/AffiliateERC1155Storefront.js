const { expect } = require("chai");
const { ethers } = require("hardhat");
const { AbiCoder } = require("ethers");
require("@nomicfoundation/hardhat-chai-matchers");

const abiCoder = new AbiCoder();
const EXAMPLE_MESSAGE = {
  encryptedData:
    "42040e12f7539ea8779f6ddf7a3dccd88c253d5dd87d5e5a624d170811a5fdaddd87a6efba872d8cfb335a2d77ef23c1dc3602e89c9eb5752a10101298671c47912f04a1f31d393bbf2890f23f3368e99fcd9b7b6dd60f1cd44f29e1dc47059ca6842290701d53f958ebbb1018e6790d1974aa76e2d4ef5c6aacf8d4c9a3e1e11164946369903b7fd0a7806aaea2ebaa",
  ephemeralPublicKey:
    "0x0447a63f06b2593890f9269cec414678f24d0da58127821800b715cd211b026c25d2c7f99bf3ff595730181a10fac12a5bad366aeb44fb5b59f51b62022fcd701f",
  iv: "ad40e6c0dae874564d01cb17",
  verificationHash:
    "0x803d7d2d2bf6f058ff2d0f43ee4e8cf872f6a8c8b5cc21daa721ba9f44b3aa76",
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

describe("AffiliateERC1155Storefront and AffiliateEscrow", function () {
  let AffiliateERC1155Storefront, affiliateERC1155Storefront;
  let AffiliateEscrow, escrowContract;
  let AffiliateEscrowFactory, escrowFactory;
  let AffiliateVerifier, affiliateVerifier;
  let MockSeaport, mockSeaport;
  let MockERC20, mockERC20;
  let MockERC1155, mockERC1155;
  let owner,
    designatedArbiter,
    addr1,
    addr2,
    addr3,
    payee,
    payer,
    arbiter,
    storefront,
    affiliate;
  let minSettleTime, initialSettleDeadline;
  let CurationStorefront, curationStorefront;

  const ItemType = {
    NATIVE: 0,
    ERC20: 1,
    ERC721: 2,
    ERC1155: 3,
    ERC721_WITH_CRITERIA: 4,
    ERC1155_WITH_CRITERIA: 5,
  };

  beforeEach(async function () {
    [
      owner,
      designatedArbiter,
      addr1,
      addr2,
      addr3,
      payee,
      payer,
      arbiter,
      storefront,
      affiliate,
    ] = await ethers.getSigners();

    MockSeaport = await ethers.getContractFactory("MockSeaport");
    mockSeaport = await MockSeaport.deploy();

    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy("MockToken", "MTK");

    MockERC1155 = await ethers.getContractFactory("MockERC1155");
    mockERC1155 = await MockERC1155.deploy();

    const AffiliateVerifierContract =
      await ethers.getContractFactory("AffiliateVerifier");
    const verifierImplementation = await AffiliateVerifierContract.deploy();

    const AffiliateVerifierProxy = await ethers.getContractFactory(
      "AffiliateVerifierProxy",
    );
    const initData =
      verifierImplementation.interface.encodeFunctionData("initialize");
    const verifierProxy = await AffiliateVerifierProxy.deploy(
      await verifierImplementation.getAddress(),
      initData,
    );

    affiliateVerifier = AffiliateVerifierContract.attach(
      await verifierProxy.getAddress(),
    );
    CurationStorefront = await ethers.getContractFactory("CurationStorefront");
    curationStorefront = await CurationStorefront.deploy();
    AffiliateEscrowFactory = await ethers.getContractFactory(
      "AffiliateEscrowFactory",
    );
    escrowFactory = await AffiliateEscrowFactory.deploy();

    minSettleTime = 7n * 24n * 60n * 60n; // 1 week
    initialSettleDeadline = 3n * 7n * 24n * 60n * 60n; // 3 weeks

    AffiliateERC1155Storefront = await ethers.getContractFactory(
      "AffiliateERC1155Storefront",
    );
    affiliateERC1155Storefront = await AffiliateERC1155Storefront.deploy(
      await mockSeaport.getAddress(),
      designatedArbiter.address,
      await escrowFactory.getAddress(),
      await mockERC1155.getAddress(),
      await affiliateVerifier.getAddress(),
      minSettleTime,
      initialSettleDeadline,
    );

    await affiliateERC1155Storefront.initialize();

    await mockERC1155.mint(
      await affiliateERC1155Storefront.getAddress(),
      1,
      100,
      "0x",
    );
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await affiliateERC1155Storefront.owner()).to.equal(owner.address);
    });

    it("Should set the right designated arbiter", async function () {
      expect(await affiliateERC1155Storefront.designatedArbiter()).to.equal(
        designatedArbiter.address,
      );
    });

    it("Should set the right Seaport address", async function () {
      expect(await affiliateERC1155Storefront.SEAPORT()).to.equal(
        await mockSeaport.getAddress(),
      );
    });

    it("Should set the right ERC1155 token address", async function () {
      expect(await affiliateERC1155Storefront.erc1155Token()).to.equal(
        await mockERC1155.getAddress(),
      );
    });

    it("Should set the right affiliate verifier", async function () {
      expect(await affiliateERC1155Storefront.affiliateVerifier()).to.equal(
        await affiliateVerifier.getAddress(),
      );
    });

    it("Should initialize with ready state as false", async function () {
      expect(await affiliateERC1155Storefront.ready()).to.be.false;
    });
  });

  describe("Ready State", function () {
    it("Should allow owner to toggle ready state", async function () {
      await affiliateERC1155Storefront.toggleReady();
      expect(await affiliateERC1155Storefront.ready()).to.be.true;

      await affiliateERC1155Storefront.toggleReady();
      expect(await affiliateERC1155Storefront.ready()).to.be.false;
    });

    it("Should not allow non-owner to toggle ready state", async function () {
      await expect(affiliateERC1155Storefront.connect(addr1).toggleReady())
        .to.be.revertedWithCustomError(
          affiliateERC1155Storefront,
          "OwnableUnauthorizedAccount",
        )
        .withArgs(addr1.address);
    });
  });

  describe("Rescue Functions", function () {
    it("Should rescue ETH correctly", async function () {
      await owner.sendTransaction({
        to: await affiliateERC1155Storefront.getAddress(),
        value: ethers.parseEther("1"),
      });

      const initialBalance = await ethers.provider.getBalance(owner.address);
      await affiliateERC1155Storefront.rescueETH(ethers.parseEther("1"));
      const finalBalance = await ethers.provider.getBalance(owner.address);

      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should rescue ERC20 tokens correctly", async function () {
      const amount = ethers.parseEther("100");
      await mockERC20.mint(
        await affiliateERC1155Storefront.getAddress(),
        amount,
      );
      await affiliateERC1155Storefront.rescueERC20(
        await mockERC20.getAddress(),
        amount,
      );
      expect(await mockERC20.balanceOf(owner.address)).to.equal(amount);
    });

    it("Should rescue ERC1155 tokens correctly", async function () {
      const id = 3;
      const amount = 100;
      await mockERC1155.mint(
        await affiliateERC1155Storefront.getAddress(),
        id,
        amount,
        "0x",
      );
      await affiliateERC1155Storefront.rescueERC1155(
        await mockERC1155.getAddress(),
        id,
        amount,
      );
      expect(await mockERC1155.balanceOf(owner.address, id)).to.equal(amount);
    });

    it("Should revert when ETH transfer fails", async function () {
      await owner.sendTransaction({
        to: await affiliateERC1155Storefront.getAddress(),
        value: ethers.parseEther("1"),
      });

      await expect(affiliateERC1155Storefront.rescueETH(ethers.parseEther("2")))
        .to.be.revertedWithCustomError(
          affiliateERC1155Storefront,
          "InsufficientBalance",
        )
        .withArgs(ethers.parseEther("2"), ethers.parseEther("1"));
    });
  });

  describe("Affiliate Integration", function () {
    const affiliateFee = 2000; // 20%

    beforeEach(async function () {
      await affiliateERC1155Storefront.listToken(
        1,
        ethers.parseEther("1"),
        ethers.ZeroAddress,
        affiliateFee,
      );
      await affiliateERC1155Storefront.toggleReady();
    });

    it("Should correctly split payment between payee and affiliate", async function () {
      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: 1,
          amount: 1,
        },
      ];

      const context = encodeContextWithAffiliateAndMessage(
        affiliate.address,
        EXAMPLE_MESSAGE,
      );

      const price = ethers.parseEther("1");

      // Record initial balances
      const initialPayeeBalance = await ethers.provider.getBalance(
        owner.address,
      );
      const initialAffiliateBalance = await ethers.provider.getBalance(
        affiliate.address,
      );

      // Generate order
      await mockSeaport.callGenerateOrder(
        await affiliateERC1155Storefront.getAddress(),
        addr1.address,
        spentItems,
        [],
        context,
      );

      // Get escrow contract
      const escrowAddress =
        await affiliateERC1155Storefront.getEscrowContract();

      // Send payment
      await addr1.sendTransaction({
        to: escrowAddress,
        value: price,
      });

      const escrow = await ethers.getContractAt(
        "AffiliateEscrow",
        escrowAddress,
      );
      await escrow.connect(addr1).settle(ethers.ZeroAddress, price);

      const expectedAffiliateAmount = (price * BigInt(affiliateFee)) / 10000n;
      const expectedPayeeAmount = price - expectedAffiliateAmount;

      const finalPayeeBalance = await ethers.provider.getBalance(owner.address);
      const finalAffiliateBalance = await ethers.provider.getBalance(
        affiliate.address,
      );

      const tolerance = ethers.parseEther("0.001"); // 0.001 ETH tolerance

      expect(finalPayeeBalance - initialPayeeBalance).to.be.closeTo(
        expectedPayeeAmount,
        tolerance,
      );
      expect(finalAffiliateBalance - initialAffiliateBalance).to.be.closeTo(
        expectedAffiliateAmount,
        tolerance,
      );
    });

    it("Should handle case with no affiliate (zero address)", async function () {
      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: 1,
          amount: 1,
        },
      ];

      const context = encodeContextWithAffiliateAndMessage(
        ethers.ZeroAddress,
        EXAMPLE_MESSAGE,
      );
      const price = ethers.parseEther("1");

      // Record initial payee balance
      const initialPayeeBalance = await ethers.provider.getBalance(
        owner.address,
      );

      // Generate order
      await mockSeaport.callGenerateOrder(
        await affiliateERC1155Storefront.getAddress(),
        addr1.address,
        spentItems,
        [],
        context,
      );

      const escrowAddress =
        await affiliateERC1155Storefront.getEscrowContract();

      // Send payment
      await addr1.sendTransaction({
        to: escrowAddress,
        value: price,
      });

      const escrow = await ethers.getContractAt(
        "AffiliateEscrow",
        escrowAddress,
      );
      await escrow.connect(addr1).settle(ethers.ZeroAddress, price);

      // With zero address affiliate, entire payment should go to payee
      const finalPayeeBalance = await ethers.provider.getBalance(owner.address);
      const tolerance = ethers.parseEther("0.001");

      expect(finalPayeeBalance - initialPayeeBalance).to.be.closeTo(
        price,
        tolerance,
      );
    });
  });

  it("Should allow setting affiliate verifier", async function () {
    const newVerifier = addr1.address;
    await affiliateERC1155Storefront.setAffiliateVerifier(newVerifier);
    expect(await affiliateERC1155Storefront.affiliateVerifier()).to.equal(
      newVerifier,
    );
  });

  describe("PreviewOrder Token Balance Check", function () {
    it("Should revert when storefront has no tokens", async function () {
      const tokenId = 999;
      const price = ethers.parseEther("1");
      const affiliateFee = 2000; // 20%

      await mockERC1155.mint(
        await affiliateERC1155Storefront.getAddress(),
        tokenId,
        1,
        "0x",
      );

      await affiliateERC1155Storefront.listToken(
        tokenId,
        price,
        ethers.ZeroAddress,
        affiliateFee,
      );
      await affiliateERC1155Storefront.toggleReady();

      await affiliateERC1155Storefront.rescueERC1155(
        await mockERC1155.getAddress(),
        tokenId,
        1,
      );

      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: tokenId,
          amount: 1,
        },
      ];

      await expect(
        affiliateERC1155Storefront.previewOrder(
          addr1.address,
          addr1.address,
          spentItems,
          [],
          "0x",
        ),
      )
        .to.be.revertedWithCustomError(
          affiliateERC1155Storefront,
          "NoTokensAvailable",
        )
        .withArgs(tokenId);
    });

    it("Should succeed when storefront has tokens", async function () {
      const tokenId = 1;
      const price = ethers.parseEther("1");
      const affiliateFee = 2000; // 20%

      await affiliateERC1155Storefront.listToken(
        tokenId,
        price,
        ethers.ZeroAddress,
        affiliateFee,
      );
      await affiliateERC1155Storefront.toggleReady();

      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: tokenId,
          amount: 1,
        },
      ];

      const result = await affiliateERC1155Storefront.previewOrder(
        addr1.address,
        addr1.address,
        spentItems,
        [],
        "0x",
      );

      expect(result.offer.length).to.equal(1);
      expect(result.offer[0].identifier).to.equal(tokenId);
    });
  });

  describe("Token Listing with Affiliate Fee", function () {
    it("Should list a token with affiliate fee correctly", async function () {
      const affiliateFee = 50; // 50/100 = 50%
      await affiliateERC1155Storefront.listToken(
        1,
        ethers.parseEther("1"),
        ethers.ZeroAddress,
        affiliateFee,
      );

      const listing = await affiliateERC1155Storefront.listings(1);
      expect(listing.tokenId).to.equal(1n);
      expect(listing.price).to.equal(ethers.parseEther("1"));
      expect(listing.paymentToken).to.equal(ethers.ZeroAddress);
      expect(listing.affiliateFee).to.equal(affiliateFee);
    });

    it("Should update a listing with new affiliate fee correctly", async function () {
      const initialAffiliateFee = 50; // 50%
      const newAffiliateFee = 70; // 70%

      await affiliateERC1155Storefront.listToken(
        1,
        ethers.parseEther("1"),
        ethers.ZeroAddress,
        initialAffiliateFee,
      );

      await affiliateERC1155Storefront.updateListing(
        1,
        ethers.parseEther("2"),
        await mockERC20.getAddress(),
        newAffiliateFee,
      );

      const listing = await affiliateERC1155Storefront.listings(1);
      expect(listing.price).to.equal(ethers.parseEther("2"));
      expect(listing.paymentToken).to.equal(await mockERC20.getAddress());
      expect(listing.affiliateFee).to.equal(newAffiliateFee);
    });

    it("Should revert when setting invalid affiliate fee", async function () {
      const invalidFee = 10001;
      await expect(
        affiliateERC1155Storefront.listToken(
          1,
          ethers.parseEther("1"),
          ethers.ZeroAddress,
          invalidFee,
        ),
      ).to.be.revertedWithCustomError(
        affiliateERC1155Storefront,
        "InvalidAffiliateFee",
      );
    });
  });

  describe("Order Generation with Affiliate", function () {
    beforeEach(async function () {
      await affiliateERC1155Storefront.listToken(
        1,
        ethers.parseEther("1"),
        ethers.ZeroAddress,
        50, // 50%
      );
      await affiliateERC1155Storefront.toggleReady();
    });

    it("Should handle order generation", async function () {
      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: 1,
          amount: 1,
        },
      ];

      const context = encodeContextWithAffiliateAndMessage(
        affiliate.address,
        EXAMPLE_MESSAGE,
      );

      // Try to generate order
      await expect(
        mockSeaport.callGenerateOrder(
          await affiliateERC1155Storefront.getAddress(),
          addr1.address,
          spentItems,
          [],
          context,
        ),
      ).to.not.be.reverted;
    });
  });

  describe("Access Control", function () {
    it("Should not allow non-owners to set affiliate verifier", async function () {
      const newVerifier = addr1.address;
      await expect(
        affiliateERC1155Storefront
          .connect(addr1)
          .setAffiliateVerifier(newVerifier),
      )
        .to.be.revertedWithCustomError(
          affiliateERC1155Storefront,
          "OwnableUnauthorizedAccount",
        )
        .withArgs(addr1.address);
    });

    it("Should not allow non-Seaport calls to generateOrder", async function () {
      await affiliateERC1155Storefront.toggleReady();
      const spentItems = [
        {
          itemType: ItemType.ERC1155,
          token: await mockERC1155.getAddress(),
          identifier: 1,
          amount: 1,
        },
      ];

      await expect(
        affiliateERC1155Storefront
          .connect(addr1)
          .generateOrder(addr1.address, spentItems, [], "0x"),
      ).to.be.revertedWithCustomError(affiliateERC1155Storefront, "NotSeaport");
    });
  });
});



  describe("CurationStorefront with Batch Operations", function () {
    let affiliateERC1155Storefront1, affiliateERC1155Storefront2;
    let curator1, curator2, nonCurator;
    let collectionId;
    const tokenIds = [1, 2, 3, 4, 5];
  
    beforeEach(async function () {
      [owner, curator1, curator2, nonCurator, ...accounts] = await ethers.getSigners();
  
      // Deploy mockERC1155
      const MockERC1155 = await ethers.getContractFactory("MockERC1155");
      mockERC1155 = await MockERC1155.deploy();
  
      // Deploy AffiliateVerifier
      const AffiliateVerifierContract = await ethers.getContractFactory("AffiliateVerifier");
      const verifierImplementation = await AffiliateVerifierContract.deploy();
      const AffiliateVerifierProxy = await ethers.getContractFactory("AffiliateVerifierProxy");
      const initData = verifierImplementation.interface.encodeFunctionData("initialize");
      const verifierProxy = await AffiliateVerifierProxy.deploy(
        await verifierImplementation.getAddress(),
        initData
      );
      const affiliateVerifier = AffiliateVerifierContract.attach(await verifierProxy.getAddress());
  
      // Deploy AffiliateEscrowFactory
      const AffiliateEscrowFactory = await ethers.getContractFactory("AffiliateEscrowFactory");
      const escrowFactory = await AffiliateEscrowFactory.deploy();
  
      // Deploy MockSeaport
      const MockSeaport = await ethers.getContractFactory("MockSeaport");
      const mockSeaport = await MockSeaport.deploy();
  
      // Deploy first storefront
      const AffiliateERC1155Storefront = await ethers.getContractFactory("AffiliateERC1155Storefront");
      affiliateERC1155Storefront1 = await AffiliateERC1155Storefront.deploy(
        await mockSeaport.getAddress(),
        accounts[0].address, // designatedArbiter
        await escrowFactory.getAddress(),
        await mockERC1155.getAddress(),
        await affiliateVerifier.getAddress(),
        7n * 24n * 60n * 60n, // minSettleTime: 1 week
        3n * 7n * 24n * 60n * 60n // initialSettleDeadline: 3 weeks
      );
      await affiliateERC1155Storefront1.initialize();
  
      // Deploy second storefront with different token address
      affiliateERC1155Storefront2 = await AffiliateERC1155Storefront.deploy(
        await mockSeaport.getAddress(),
        accounts[0].address, // designatedArbiter
        await escrowFactory.getAddress(),
        await mockERC1155.getAddress(),
        await affiliateVerifier.getAddress(),
        7n * 24n * 60n * 60n, // minSettleTime: 1 week
        3n * 7n * 24n * 60n * 60n // initialSettleDeadline: 3 weeks
      );
      await affiliateERC1155Storefront2.initialize();
  
      // Mint tokens to the storefronts
      for (let i = 0; i < tokenIds.length; i++) {
        await mockERC1155.mint(
          await affiliateERC1155Storefront1.getAddress(),
          tokenIds[i],
          100,
          "0x"
        );
        await mockERC1155.mint(
          await affiliateERC1155Storefront2.getAddress(),
          tokenIds[i] + 100, // Use different token IDs for second storefront
          100,
          "0x"
        );
      }
  
      // List tokens in storefronts
      for (let i = 0; i < tokenIds.length; i++) {
        await affiliateERC1155Storefront1.listToken(
          tokenIds[i],
          ethers.parseEther("1"),
          ethers.ZeroAddress,
          2000 // 20% affiliate fee
        );
        await affiliateERC1155Storefront2.listToken(
          tokenIds[i] + 100,
          ethers.parseEther("2"),
          ethers.ZeroAddress,
          2500 // 25% affiliate fee
        );
      }
      
      await affiliateERC1155Storefront1.toggleReady();
      await affiliateERC1155Storefront2.toggleReady();
  
      // Deploy CurationStorefront
      const CurationStorefront = await ethers.getContractFactory("CurationStorefront");
      curationStorefront = await CurationStorefront.deploy();
  
      // Create a curation
      const tx = await curationStorefront.createCuration(
        "Test Collection",
        "Description for test collection",
        owner.address,
        "ipfs://test"
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(log => log.fragment?.name === "CurationCreated");
      collectionId = event.args.curationId;
  
      // Add curator1 as a curator
      await curationStorefront.addCurator(collectionId, curator1.address);
    });
  
    describe("Metadata Management", function() {
      it("Should allow token owner to update curation metadata", async function() {
        const newURI = "ipfs://updated-metadata";
        
        const tx = await curationStorefront.setCurationMetadata(
          collectionId,
          newURI
        );
        
        const receipt = await tx.wait();
        const event = receipt.logs.find(log => log.fragment?.name === "MetadataUpdated");
        
        expect(event.args.curationId).to.equal(collectionId);
        expect(event.args.newTokenURI).to.equal(newURI);
        
        // Verify the token URI was updated
        expect(await curationStorefront.tokenURI(collectionId)).to.equal(newURI);
      });
  
      it("Should not allow non-owner to update curation metadata", async function() {
        await expect(
          curationStorefront.connect(curator1).setCurationMetadata(
            collectionId,
            "ipfs://unauthorized-update"
          )
        ).to.be.revertedWithCustomError(curationStorefront, "NotTokenOwner");
      });
    });
  
    describe("Batch Curator Listing Operations", function () {
      it("Should allow creating multiple curated listings from a single storefront", async function () {
        const listingsToAdd = [];
        for (let i = 0; i < 3; i++) {
          listingsToAdd.push({
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[i]
          });
        }
  
        const tx = await curationStorefront.connect(curator1).batchCurateListings(
          collectionId,
          listingsToAdd
        );
        
        const receipt = await tx.wait();
        const events = receipt.logs.filter(log => log.fragment?.name === "ListingCurated");
        
        expect(events.length).to.equal(3);
        for (let i = 0; i < 3; i++) {
          expect(events[i].args.curationId).to.equal(collectionId);
          expect(events[i].args.storefrontAddress).to.equal(await affiliateERC1155Storefront1.getAddress());
          expect(events[i].args.tokenId).to.equal(tokenIds[i]);
        }
      });
  
      it("Should allow creating curated listings from different storefronts", async function () {
        const mixedListings = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          },
          {
            storefrontAddress: await affiliateERC1155Storefront2.getAddress(),
            tokenId: tokenIds[0] + 100
          },
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[1]
          }
        ];
  
        const tx = await curationStorefront.connect(curator1).batchCurateListings(
          collectionId,
          mixedListings
        );
        
        const receipt = await tx.wait();
        const events = receipt.logs.filter(log => log.fragment?.name === "ListingCurated");
        
        expect(events.length).to.equal(3);
        
        // Check first listing
        expect(events[0].args.storefrontAddress).to.equal(await affiliateERC1155Storefront1.getAddress());
        expect(events[0].args.tokenId).to.equal(tokenIds[0]);
        
        // Check second listing
        expect(events[1].args.storefrontAddress).to.equal(await affiliateERC1155Storefront2.getAddress());
        expect(events[1].args.tokenId).to.equal(tokenIds[0] + 100);
        
        // Check third listing
        expect(events[2].args.storefrontAddress).to.equal(await affiliateERC1155Storefront1.getAddress());
        expect(events[2].args.tokenId).to.equal(tokenIds[1]);
      });
  
      it("Should revert if batch size exceeds maximum", async function () {
        const tooManyListings = [];
        for (let i = 0; i < 21; i++) { // Create 21 listings (MAX_BATCH_SIZE is 20)
          tooManyListings.push({
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[i % tokenIds.length]
          });
        }
  
        await expect(
          curationStorefront.connect(curator1).batchCurateListings(collectionId, tooManyListings)
        ).to.be.revertedWithCustomError(curationStorefront, "BatchSizeInvalid");
      });
  
      it("Should revert if batch is empty", async function () {
        await expect(
          curationStorefront.connect(curator1).batchCurateListings(collectionId, [])
        ).to.be.revertedWithCustomError(curationStorefront, "BatchSizeInvalid");
      });
  
      it("Should revert if any listing is not found in storefront", async function () {
        const listingsWithInvalid = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          },
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: 999 // This token ID doesn't exist
          }
        ];
  
        await expect(
          curationStorefront.connect(curator1).batchCurateListings(collectionId, listingsWithInvalid)
        ).to.be.revertedWithCustomError(curationStorefront, "ListingNotFound");
      });
  
      it("Should not allow non-curator to batch add listings", async function () {
        const listingsToAdd = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          }
        ];
  
        await expect(
          curationStorefront.connect(nonCurator).batchCurateListings(collectionId, listingsToAdd)
        ).to.be.revertedWithCustomError(curationStorefront, "NotCurator");
      });
    });
  
    describe("Batch Update Operations", function () {
      let listingIds = [];
  
      beforeEach(async function () {
        // Add 5 listings to update
        const listingsToAdd = [];
        for (let i = 0; i < 5; i++) {
          listingsToAdd.push({
            storefrontAddress: i % 2 === 0 
              ? await affiliateERC1155Storefront1.getAddress() 
              : await affiliateERC1155Storefront2.getAddress(),
            tokenId: i % 2 === 0 ? tokenIds[i] : tokenIds[i] + 100
          });
        }
  
        const tx = await curationStorefront.connect(curator1).batchCurateListings(
          collectionId,
          listingsToAdd
        );
        
        const receipt = await tx.wait();
        const events = receipt.logs.filter(log => log.fragment?.name === "ListingCurated");
        
        // Extract listing IDs for testing
        listingIds = events.map(event => event.args.listingId);
      });
  
      it("Should allow batch updating active state of listings", async function () {
        const listingIdsToUpdate = [listingIds[0], listingIds[2], listingIds[4]];
        const activeStates = [false, false, false];
  
        const tx = await curationStorefront.connect(curator1).batchUpdateListings(
          collectionId,
          listingIdsToUpdate,
          activeStates
        );
        
        const receipt = await tx.wait();
        const events = receipt.logs.filter(log => log.fragment?.name === "ListingUpdated");
        
        expect(events.length).to.equal(3);
        
        // Check each listing was updated correctly
        for (let i = 0; i < listingIdsToUpdate.length; i++) {
          expect(events[i].args.curationId).to.equal(collectionId);
          expect(events[i].args.listingId).to.equal(listingIdsToUpdate[i]);
          expect(events[i].args.active).to.equal(activeStates[i]);
          
          // Also verify via getCuratedListing
          const listing = await curationStorefront.getCuratedListing(collectionId, listingIdsToUpdate[i]);
          expect(listing.active).to.equal(activeStates[i]);
        }
        
        // Check that other listings remain active
        const unchangedListing = await curationStorefront.getCuratedListing(collectionId, listingIds[1]);
        expect(unchangedListing.active).to.be.true;
      });
  
      it("Should allow toggling active state multiple times", async function () {
        // First update - set to inactive
        await curationStorefront.connect(curator1).batchUpdateListings(
          collectionId,
          [listingIds[0]],
          [false]
        );
        
        // Verify it's inactive
        let listing = await curationStorefront.getCuratedListing(collectionId, listingIds[0]);
        expect(listing.active).to.be.false;
        
        // Second update - set back to active
        await curationStorefront.connect(curator1).batchUpdateListings(
          collectionId,
          [listingIds[0]],
          [true]
        );
        
        // Verify it's active again
        listing = await curationStorefront.getCuratedListing(collectionId, listingIds[0]);
        expect(listing.active).to.be.true;
      });
  
      it("Should revert if any listing ID is invalid", async function () {
        const invalidListingIds = [listingIds[0], 999]; // 999 doesn't exist
        const activeStates = [false, false];
  
        await expect(
          curationStorefront.connect(curator1).batchUpdateListings(
            collectionId, 
            invalidListingIds,
            activeStates
          )
        ).to.be.revertedWithCustomError(curationStorefront, "ListingNotFound");
      });
  
      it("Should revert if array lengths don't match", async function () {
        const listingIdsToUpdate = [listingIds[0], listingIds[1]];
        const activeStates = [false]; // Only one value
  
        await expect(
          curationStorefront.connect(curator1).batchUpdateListings(
            collectionId,
            listingIdsToUpdate,
            activeStates
          )
        ).to.be.revertedWith("Length mismatch");
      });
  
      it("Should not allow non-curator to batch update listings", async function () {
        await expect(
          curationStorefront.connect(nonCurator).batchUpdateListings(
            collectionId,
            [listingIds[0]],
            [false]
          )
        ).to.be.revertedWithCustomError(curationStorefront, "NotCurator");
      });
  
      it("Should revert if batch update is empty", async function () {
        await expect(
          curationStorefront.connect(curator1).batchUpdateListings(
            collectionId, 
            [], 
            []
          )
        ).to.be.revertedWithCustomError(curationStorefront, "BatchSizeInvalid");
      });
  
      it("Should revert if batch size exceeds maximum", async function () {
        const tooManyIds = [];
        const tooManyStates = [];
        for (let i = 0; i < 21; i++) { // MAX_BATCH_SIZE is 20
          tooManyIds.push(listingIds[0]);
          tooManyStates.push(false);
        }
  
        await expect(
          curationStorefront.connect(curator1).batchUpdateListings(
            collectionId,
            tooManyIds,
            tooManyStates
          )
        ).to.be.revertedWithCustomError(curationStorefront, "BatchSizeInvalid");
      });
    });
  
    describe("Curation Management and Curator Roles", function () {
      it("Should handle adding and then updating listings in sequence", async function () {
        // First add some listings
        const listingsToAdd = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          },
          {
            storefrontAddress: await affiliateERC1155Storefront2.getAddress(),
            tokenId: tokenIds[0] + 100
          }
        ];
  
        const addTx = await curationStorefront.connect(curator1).batchCurateListings(
          collectionId,
          listingsToAdd
        );
        
        const addReceipt = await addTx.wait();
        const addEvents = addReceipt.logs.filter(log => log.fragment?.name === "ListingCurated");
        
        const listingIds = addEvents.map(event => event.args.listingId);
        
        // Then update the listings
        await curationStorefront.connect(curator1).batchUpdateListings(
          collectionId,
          [listingIds[0]],
          [false]
        );
        
        // Verify both listings via getCuratedListing
        const listing1 = await curationStorefront.getCuratedListing(collectionId, listingIds[0]);
        const listing2 = await curationStorefront.getCuratedListing(collectionId, listingIds[1]);
        
        expect(listing1.active).to.be.false;
        expect(listing2.active).to.be.true;
      });
  
      it("Should allow owner to add curator who can then use batch operations", async function () {
        // Add curator2 as curator
        await curationStorefront.addCurator(collectionId, curator2.address);
        
        // Verify curator2 is a curator
        expect(await curationStorefront.isCurator(collectionId, curator2.address)).to.be.true;
        
        // Have curator2 add listings
        const listingsToAdd = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          }
        ];
  
        await expect(
          curationStorefront.connect(curator2).batchCurateListings(collectionId, listingsToAdd)
        ).to.not.be.reverted;
      });
      
      it("Should properly revoke curator status", async function () {
        // Add curator2 as curator
        await curationStorefront.addCurator(collectionId, curator2.address);
        expect(await curationStorefront.isCurator(collectionId, curator2.address)).to.be.true;
        
        // Remove curator2
        await curationStorefront.removeCurator(collectionId, curator2.address);
        expect(await curationStorefront.isCurator(collectionId, curator2.address)).to.be.false;
        
        // Attempt to add a listing should now fail
        const listingsToAdd = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          }
        ];
  
        await expect(
          curationStorefront.connect(curator2).batchCurateListings(collectionId, listingsToAdd)
        ).to.be.revertedWithCustomError(curationStorefront, "NotCurator");
      });
    });
  
    describe("View Functions and Data Retrieval", function () {
      it("Should handle listing token data from both storefront types", async function () {
        // Add listings from both types of storefronts
        const listingsToAdd = [
          {
            storefrontAddress: await affiliateERC1155Storefront1.getAddress(),
            tokenId: tokenIds[0]
          },
          {
            storefrontAddress: await affiliateERC1155Storefront2.getAddress(),
            tokenId: tokenIds[0] + 100
          }
        ];
  
        const tx = await curationStorefront.connect(curator1).batchCurateListings(
          collectionId,
          listingsToAdd
        );
        
        const receipt = await tx.wait();
        const events = receipt.logs.filter(log => log.fragment?.name === "ListingCurated");
        
        const listingIds = events.map(event => event.args.listingId);
        
        // Get data for both listings
        const listing1 = await curationStorefront.getCuratedListing(collectionId, listingIds[0]);
        const listing2 = await curationStorefront.getCuratedListing(collectionId, listingIds[1]);
        
        // Verify storefront 1 data
        expect(listing1.storefrontAddress).to.equal(await affiliateERC1155Storefront1.getAddress());
        expect(listing1.tokenId).to.equal(tokenIds[0]);
        expect(listing1.price).to.equal(ethers.parseEther("1"));
        expect(listing1.affiliateFee).to.equal(2000);
        
        // Verify storefront 2 data
        expect(listing2.storefrontAddress).to.equal(await affiliateERC1155Storefront2.getAddress());
        expect(listing2.tokenId).to.equal(tokenIds[0] + 100);
        expect(listing2.price).to.equal(ethers.parseEther("2"));
        expect(listing2.affiliateFee).to.equal(2500);
      });
  
      it("Should fetch correct curation details", async function () {
        const details = await curationStorefront.getCurationDetails(collectionId);
        
        expect(details.name).to.equal("Test Collection");
        expect(details.description).to.equal("Description for test collection");
        expect(details.paymentAddress).to.equal(owner.address);
        expect(details.owner).to.equal(owner.address);
      });
  
      it("Should revert when requesting non-existent curation", async function () {
        const nonExistentId = 999;
        
        await expect(
          curationStorefront.getCurationDetails(nonExistentId)
        ).to.be.revertedWithCustomError(curationStorefront, "CurationNotFound");
      });
  
      it("Should retrieve ERC1155 token address from listing", async function () {
        // Add a listing
        const tx = await curationStorefront.connect(curator1).curateListing(
          collectionId,
          await affiliateERC1155Storefront1.getAddress(),
          tokenIds[0]
        );
        
        const receipt = await tx.wait();
        const event = receipt.logs.find(log => log.fragment?.name === "ListingCurated");
        const listingId = event.args.listingId;
        
        // Get the ERC1155 token address
        const erc1155Address = await curationStorefront.getListingERC1155Token(
          collectionId,
          listingId
        );
        
        expect(erc1155Address).to.equal(await mockERC1155.getAddress());
      });
    });
  });




