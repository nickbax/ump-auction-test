# Auction House Smart Contract System

## Overview

The Auction House system is a comprehensive solution for creating and managing on-chain NFT auctions with premium bidding features, anti-sniping protections, and secure escrow-based settlement. This system supports both traditional auctions and premium auctions where outbid participants receive compensation.

## Key Features

- **Multiple Auction Houses**: Create distinct auction houses for different collections or themes
- **Customizable Auctions**: Configure reserve prices, durations, extensions, and more
- **Premium Bidding**: Option to give outbid participants a percentage of the bid increment as compensation
- **Anti-Sniping**: Automatic time extensions when bids are placed near the end of an auction
- **Affiliate Support**: Integrated affiliate system with customizable commission rates
- **Secure Escrow**: All payments are held in escrow until the transaction completes
- **Dispute Resolution**: Built-in arbitration system for handling disputes
- **Encrypted Messaging**: Support for encrypted communication between buyers and sellers
- **NFT Minting**: Create new NFTs directly within the auction system
- **TheGraph Integration**: Complete event tracking for analytics and user interfaces

## Architecture

The system consists of several interconnected smart contracts:

- **AuctionHouse**: Main contract for managing auctions
- **AuctionHouseFactory**: Creates new auction house instances
- **AuctionItemERC721**: ERC721 implementation for auction items
- **AuctionItemERC721Factory**: Creates new NFT collection contracts
- **AffiliateEscrow**: Secures payments until settlement
- **AffiliateEscrowFactory**: Creates new escrow contracts
- **AffiliateVerifier**: Validates affiliate addresses and determines commission rates

## Auction Flow

1. **Create Auction House**: Deploy a new auction house using the factory
2. **Create Auction**: Set up an auction with desired parameters
3. **Bidding Period**: Users place bids during the auction timeframe
4. **Auction End**: NFT transfers to winner, payment goes to escrow
5. **Settlement**: Buyer receives item and confirms, seller receives payment
6. **Optional Dispute**: If issues arise, the designated arbiter resolves

## Premium Auction Mechanics

Premium auctions incentivize bidding by returning a percentage of the bid increment to outbid participants:

- Each bid must exceed the previous by at least the minimum increment (e.g., 5%)
- When outbid, the previous bidder receives their bid amount plus a premium
- Premium is calculated as a percentage of the minimum increment
- Example: With a 1 ETH current bid, 5% increment, and 50% premium rate:
  - Minimum next bid: 1.05 ETH
  - Premium to outbid user: 0.025 ETH (50% of the 0.05 ETH increment)
  - Outbid user receives: 1.025 ETH

## Anti-Sniping Protection

To prevent last-second bidding strategies:

- If a bid is placed within the timeExtension period of the end time
- The auction is automatically extended by the timeExtension duration
- This gives other participants a fair chance to respond
- Ensures auctions end due to lack of interest, not timing tricks

## Escrow System

All auction payments are processed through an escrow system:

- Funds remain in escrow until the transaction completes
- Buyers can confirm receipt and release payment
- Sellers can refund buyers if needed
- Designated arbiters can resolve disputes
- Escrow supports affiliate payments with configurable rates

## Integration with The Graph

The system is designed to work with The Graph for indexing and analytics:

- Track all auction activities
- Monitor bidding patterns
- Analyze premium distributions
- Record settlement and dispute outcomes
- Support for advanced querying and reporting

## Contract Deployment

1. Deploy the factory contracts first:
   - AuctionItemERC721Factory
   - AffiliateEscrowFactory
   - AuctionHouseFactory

2. Create an auction house through the factory:
```solidity
auctionHouseFactory.createAuctionHouse(
    "My Auction House",
    "https://example.com/image.png",
    "Description of auction house",
    "https://example.com/metadata.json",
    "MAH",
    1814400, // 21 days settlement deadline
    auctionItemERC721FactoryAddress,
    affiliateEscrowFactoryAddress
);
```

3. Create auctions through the auction house:
```solidity
auctionHouse.createAuction(
    nftContractAddress,
    tokenId,
    startTime,
    reservePrice,
    duration,
    affiliateFee,
    arbiterAddress,
    escrowFactoryAddress,
    paymentTokenAddress, // address(0) for ETH
    isPremiumAuction,
    premiumBasisPoints,
    minBidIncrementBps,
    timeExtension
);
```

## Security Considerations

- Non-reentrancy guards on critical functions
- Escrow-based payment handling
- Clear access controls
- Emergency rescue functions for stuck assets
- Time-based settlement deadlines

## License

GPL-3.0

---

© 2024 - Auction House System
