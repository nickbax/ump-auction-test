// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAuctionHouse} from "./interfaces/IAuctionHouse.sol";
import {AffiliateEscrowFactory} from "./AffiliateEscrowFactory.sol";
import {AffiliateEscrow} from "./AffiliateEscrow.sol";

// Custom errors
error AuctionNotActive();
error AuctionExpired();
error BidBelowReservePrice();
error BidIncrementTooLow();
error AuctionEndedOrCanceled();
error AuctionHasntStarted();
error AuctionHasntCompleted();
error AuctionHasBid();
error AuctionStillActive();
error NotWinner();

// Encrypted Message Struct
struct EncryptedMessage {
    /// @dev The encrypted payload using the seller's public key
    bytes encryptedData;
    /// @dev The ephemeral public key from the buyer
    bytes ephemeralPublicKey;
    /// @dev The initialization vector used in the encryption
    bytes iv;
    /// @dev A hash used to verify correctness
    bytes verificationHash;
}

contract AuctionHouse is IAuctionHouse, ReentrancyGuard {
    /// @notice A user-friendly name for this auction instance.
    string public name;

    /// @notice A user-friendly image URL for this auction (e.g. IPFS link).
    string public image;

    /// @notice A text description for this auction.
    string public description;

    /// @notice Versioning info (like 0.0.3, etc.).
    string public constant VERSION = "0.0.1";

    /**
     * @dev A percentage that sets how much higher a new bid must be
     *      than the current highest bid, expressed in basis points
     *      (e.g. 500 means 5%).
     */
    uint16 public minBidIncrementBps;

    IAuctionHouse.Auction public auction;
    bool public isActive;

    // Stores the highest bidder's attached message, if any
    EncryptedMessage public topBidEncryptedMessage;

    /// @notice Emitted when a bidder attaches an encrypted message to their bid.
    event AuctionEncryptedMessage(
        address indexed auctionAddress,
        address indexed bidder,
        bytes encryptedData,
        bytes ephemeralPublicKey,
        bytes iv,
        bytes verificationHash,
        bool isFinal
    );

    constructor(
        string memory _name,               // e.g. "My Exclusive Auction"
        string memory _image,              // e.g. "ipfs://hash/image.jpg"
        string memory _description,        // e.g. "A special 1/1 digital art piece"
        address _arbiter,
        address _escrowFactory,
        address _erc721Token,             // Contract address of the ERC-721 token being auctioned
        uint256 _tokenId,                 // Token ID for that ERC-721
        uint256 _reservePrice,            // Starting price for the auction
        uint256 _duration,                // Auction duration in seconds
        uint16 _affiliateFee,             // Affiliate fee in basis points e.g. 100 = 1%
        uint16 _minBidIncrementBps_,      // A percentage that sets how much higher a new bid must be
        address _auctionCurrency         // The address of the ERC-20 currency to run the auction in.
    ) {
        name = _name;
        image = _image;
        description = _description;
        minBidIncrementBps = _minBidIncrementBps_;

        auction = IAuctionHouse.Auction({
            tokenId: _tokenId,
            tokenContract: _erc721Token,
            amount: 0,
            duration: _duration,
            firstBidTime: 0,
            reservePrice: _reservePrice,
            affiliateFee: _affiliateFee,
            auctionOwner: msg.sender, // The user deploying is the auctionOwner
            bidder: payable(address(0)),
            affiliate: address(0),
            arbiter: _arbiter,
            escrow: address(0),
            auctionCurrency: _auctionCurrency
        });

        // Transfer the NFT to this AuctionHouse contract
        IERC721(_erc721Token).transferFrom(msg.sender, address(this), _tokenId);

        // Create a fresh escrow contract for final payouts
        address escrowAddress = AffiliateEscrowFactory(_escrowFactory).createEscrow(
            auction.auctionOwner,
            address(this),
            _arbiter
        );
        auction.escrow = escrowAddress;

        isActive = true;

        emit AuctionCreated(
            address(this),
            msg.sender,
            _erc721Token,
            _tokenId,
            _duration,
            _reservePrice,
            _affiliateFee,
            _arbiter
        );
    }

    /**
     * @notice Create a bid on the auction, optionally attaching an encrypted message.
     * @dev If provided a valid bid, refunds the previous bidder if there is one.
     *      The new bid must be at least `auction.amount + (auction.amount * minBidIncrementBps) / 10000`.
     * @param _affiliate The affiliate address, if any, used by the bidder.
     * @param _encryptedMsg An optional encrypted message from the bidder.
     */
    function createBid(
        address _affiliate,
        EncryptedMessage calldata _encryptedMsg
    ) external payable override nonReentrant {
        if (!isActive) {
            revert AuctionNotActive();
        }

        // If the auction has started, enforce that it's not expired
        if (auction.firstBidTime != 0) {
            if (block.timestamp >= auction.firstBidTime + auction.duration) {
                revert AuctionExpired();
            }
        }

        // Enforce minimum reserve price
        if (msg.value < auction.reservePrice) {
            revert BidBelowReservePrice();
        }

        // Enforce minBidIncrementBps in basis points (1 BPS = 0.01%)
        uint256 minimumNextBid = auction.amount + (
            (auction.amount * minBidIncrementBps) / 10000
        );
        if (msg.value < minimumNextBid) {
            revert BidIncrementTooLow();
        }

        // Refund the previous highest bidder (if any)
        if (auction.bidder != address(0)) {
            uint256 prevBidAmount = auction.amount;
            payable(auction.bidder).transfer(prevBidAmount);
        }

        // If this is the first valid bid, record the auction start time
        if (auction.firstBidTime == 0) {
            auction.firstBidTime = block.timestamp;
        }

        // Record the new highest bidder, affiliate, and bid
        auction.bidder = payable(msg.sender);
        auction.affiliate = _affiliate;
        auction.amount = msg.value;

        // Store the new top bidder's encrypted message
        topBidEncryptedMessage = _encryptedMsg;

        // Emit standard AuctionBid event
        emit AuctionBid(
            address(this),
            msg.sender,
            _affiliate,
            msg.value,
            (auction.firstBidTime == block.timestamp)
        );

        // Emit a separate event if there's any encrypted data
        bool hasEncryptedData = (
            _encryptedMsg.encryptedData.length != 0 ||
            _encryptedMsg.ephemeralPublicKey.length != 0 ||
            _encryptedMsg.iv.length != 0 ||
            _encryptedMsg.verificationHash.length != 0
        );
        if (hasEncryptedData) {
            emit AuctionEncryptedMessage(
                address(this),
                msg.sender,
                _encryptedMsg.encryptedData,
                _encryptedMsg.ephemeralPublicKey,
                _encryptedMsg.iv,
                _encryptedMsg.verificationHash,
                false // not final
            );
        }
    }

    /**
     * @notice End the auction, finalizing the sale and forwarding funds to escrow.
     * @dev The escrow contract is then responsible for distributing payouts.
     */
    function endAuction() external override nonReentrant {
        if (!isActive) {
            revert AuctionEndedOrCanceled();
        }
        if (auction.firstBidTime == 0) {
            revert AuctionHasntStarted();
        }
        if (block.timestamp < auction.firstBidTime + auction.duration) {
            revert AuctionHasntCompleted();
        }

        isActive = false;

        // Transfer the NFT from AuctionHouse to the winning bidder
        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        // Send the final bid amount to the escrow
        payable(auction.escrow).transfer(auction.amount);

        // Log approximate affiliate share in the event (for reference)
        uint256 affiliateShare = (auction.amount * auction.affiliateFee) / 10000;

        emit AuctionEnded(
            address(this),
            auction.bidder,
            auction.affiliate,
            auction.amount,
            affiliateShare
        );
    }

    /**
     * @notice Cancel an auction if no bids have been placed and return NFT to the owner.
     */
    function cancelAuction() external override nonReentrant {
        if (!isActive) {
            revert AuctionEndedOrCanceled();
        }
        if (auction.bidder != address(0)) {
            revert AuctionHasBid();
        }

        isActive = false;

        // Return the NFT to the auctionOwner
        IERC721(auction.tokenContract).transferFrom(address(this), auction.auctionOwner, auction.tokenId);

        emit AuctionCanceled(
            address(this),
            auction.auctionOwner
        );
    }

    /**
     * @notice Once the auction is ended, the winning bidder can update their
     *         encrypted message using the seller's encryption key, if desired.
     * @dev Will emit an event with isFinal = true.
     */
    function setWinningBidderEncryptedMessage(
        EncryptedMessage calldata newMsg
    ) external {
        // Auction must have ended
        if (isActive) {
            revert AuctionStillActive();
        }
        // Only the winning bidder can update
        if (auction.bidder != msg.sender) {
            revert NotWinner();
        }

        // Update the topBidEncryptedMessage
        topBidEncryptedMessage = newMsg;

        // Emit event with isFinal = true
        emit AuctionEncryptedMessage(
            address(this),
            msg.sender,
            newMsg.encryptedData,
            newMsg.ephemeralPublicKey,
            newMsg.iv,
            newMsg.verificationHash,
            true
        );
    }
}