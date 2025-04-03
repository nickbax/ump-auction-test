// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAuctionHouse} from "./interfaces/IAuctionHouse.sol";
import {AffiliateEscrowFactory} from "./AffiliateEscrowFactory.sol";
import {AffiliateEscrow} from "./AffiliateEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
error AuctionNotFound();
error NotWinner();
error InvalidPremiumPercentage();
error TransferFailed();
error NotAuctionOwner();
error AuctionAlreadyActive();
error NFTNotHeldByContract();

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

struct Auction {
    uint256 tokenId;
    address tokenContract;
    uint256 amount;
    uint256 duration;
    uint256 startTime;
    uint256 reservePrice;
    uint16 affiliateFee;
    address auctionOwner;
    address payable bidder;
    address affiliate;
    address arbiter;
    address escrowAddress;
    address auctionCurrency;
    uint16 minBidIncrementBps;
    bool isPremiumAuction;
    uint16 premiumBps;
    uint256 timeExtension;
}

contract AuctionHouse is IAuctionHouse, ReentrancyGuard {
    /// @notice A user-friendly name for this auction house.
    string public name;
    
    /// @notice An image URL for this auction house (e.g. IPFS link).
    string public image;
    
    /// @notice A text description for this auction house.
    string public description;

    /// @notice Owner of the auction house
    address public owner;

    /// @notice Versioning info
    string public constant VERSION = "0.0.2";

    // Counter for creating new auction IDs
    uint256 private nextAuctionId;

    // Auction data
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public auctionExists;
    mapping(uint256 => EncryptedMessage) public auctionEncryptedMessages;
    mapping(address => mapping(uint256 => uint256)) public tokenToAuctionId; // Maps token contract + tokenId to auctionId
    

    /// @notice Emitted when a bidder attaches an encrypted message to their bid.
    event AuctionEncryptedMessage(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed bidder,
        bytes encryptedData,
        bytes ephemeralPublicKey,
        bytes iv,
        bytes verificationHash,
        bool isFinal
    );

    /// @notice Emitted when a premium is paid to an outbid user
    event PremiumPaid(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed outbidUser,
        address newBidder,
        uint256 originalBid,
        uint256 premiumAmount
    );

    /// @notice Emitted when an auction is extended due to a late bid
    event AuctionExtended(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        uint256 newEndTime
    );


    constructor(
        string memory _name,                // Name of the auction house
        string memory _image,               // Image URL for the auction house
        string memory _description,         // Description of the auction house
        address _owner                      // Owner of the auction house
    ) {
        name = _name;
        image = _image;
        description = _description;
        owner = _owner;
        
        // Start auction IDs at 1
        nextAuctionId = 1;
    }

    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _startTime,
        uint256 _reservePrice,
        uint256 _duration,
        uint16 _affiliateFee,
        address _arbiter,
        address _escrowFactory,
        address _auctionCurrency,
        bool _isPremiumAuction,
        uint16 _premiumBps,
        uint16 _minBidIncrementBps,
        uint256 _timeExtension
    ) external returns (uint256) {
        // Check if token is already being auctioned
        if (tokenToAuctionId[_tokenContract][_tokenId] != 0) {
            revert("Token already in auction");
        }
        
        // Verify that this contract holds the NFT
        if(IERC721(_tokenContract).ownerOf(_tokenId) != address(this)) {
            revert NFTNotHeldByContract();
        }
        
        // Validate premium percentage
        if (_isPremiumAuction && _premiumBps > 10000) {
            revert InvalidPremiumPercentage();
        }
        
        // Validate start time is in the future
        require(_startTime > block.timestamp, "Start time must be in the future");
        
        // Generate auction ID and increment by 1
        uint256 auctionId = nextAuctionId++;
        
        // Create a new auction
        auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            amount: _reservePrice,  // Set initial amount to reserve price
            duration: _duration,
            startTime: _startTime,
            reservePrice: _reservePrice,
            affiliateFee: _affiliateFee,
            auctionOwner: msg.sender,
            bidder: payable(address(0)),
            affiliate: address(0),
            arbiter: _arbiter,
            escrowAddress: address(0),
            auctionCurrency: _auctionCurrency,
            minBidIncrementBps: _minBidIncrementBps,
            isPremiumAuction: _isPremiumAuction,
            premiumBps: _premiumBps,
            timeExtension: _timeExtension
        });
        
        // Create a fresh escrow contract for final payouts
        address escrowAddress = AffiliateEscrowFactory(_escrowFactory).createEscrow(
            msg.sender, // auction owner
            address(this),
            _arbiter
        );
        auctions[auctionId].escrowAddress = escrowAddress;
        
        // Register auction
        auctionExists[auctionId] = true;
        tokenToAuctionId[_tokenContract][_tokenId] = auctionId;
        
        // Emit auction created event
        emit AuctionCreated(
            auctionId,
            address(this),
            msg.sender,
            _tokenContract,
            _tokenId,
            _duration,
            _reservePrice,
            _affiliateFee,
            _arbiter,
            escrowAddress,
            _isPremiumAuction
        );
        
        return auctionId;
    }

    /**
     * @notice Create a bid on an auction, optionally attaching an encrypted message.
     * @param _auctionId The auction to bid on
     * @param _affiliate The affiliate address, if any, used by the bidder
     * @param _encryptedMsg An optional encrypted message from the bidder
     */
    function createBid(
        uint256 _auctionId,
        address _affiliate,
        EncryptedMessage calldata _encryptedMsg
    ) external payable nonReentrant {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Check if auction has started
        if (block.timestamp < auction.startTime) {
            revert AuctionNotActive();
        }

        // Check if auction has expired
        if (block.timestamp >= auction.startTime + auction.duration) {
            revert AuctionExpired();
        }

        // Enforce minimum reserve price
        if (msg.value < auction.reservePrice) {
            revert BidBelowReservePrice();
        }

        // Enforce minBidIncrementBps in basis points (1 BPS = 0.01%)
        uint256 minimumNextBid = auction.amount + (
            (auction.amount * auction.minBidIncrementBps) / 10000
        );
        if (msg.value < minimumNextBid) {
            revert BidIncrementTooLow();
        }
        
        uint256 auctionEndTime = auction.startTime + auction.duration;
        if (auctionEndTime - block.timestamp < auction.timeExtension) {
            // Extend the auction by timeExtension from current time
            auction.duration = (block.timestamp - auction.startTime) + auction.timeExtension;
            emit AuctionExtended(_auctionId, address(this), auction.startTime + auction.duration);
        }

        // Refund the previous highest bidder (if any), with premium if applicable
        if (auction.bidder != address(0)) {
            address payable previousBidder = auction.bidder;
            uint256 prevBidAmount = auction.amount;
            
            if (auction.isPremiumAuction && auction.premiumBps > 0) {
                // Calculate the premium based on the minimum bid increment, not the actual increment
                uint256 minIncrement = (prevBidAmount * auction.minBidIncrementBps) / 10000;
                uint256 premium = (minIncrement * auction.premiumBps) / 10000;
                
                // Transfer original bid amount plus premium
                previousBidder.transfer(prevBidAmount + premium);
                
                // Emit event for premium payment
                emit PremiumPaid(
                    _auctionId,
                    address(this),
                    previousBidder,
                    msg.sender,
                    prevBidAmount,
                    premium
                );
            } else {
                // Standard refund without premium
                previousBidder.transfer(prevBidAmount);
            }
        }

    // Record the new highest bidder, affiliate, and bid
    auction.bidder = payable(msg.sender);
    auction.affiliate = _affiliate;
    auction.amount = msg.value;

    // Store the new top bidder's encrypted message
    auctionEncryptedMessages[_auctionId] = _encryptedMsg;

    // Emit standard AuctionBid event
    emit AuctionBid(
        _auctionId,
        address(this),
        msg.sender,
        _affiliate,
        msg.value,
        false
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
            _auctionId,
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
     * @notice End an auction, finalizing the sale and forwarding funds to escrow.
     * @param _auctionId The ID of the auction to end
     */
    function endAuction(uint256 _auctionId) external nonReentrant {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        if (block.timestamp < auction.startTime + auction.duration) {
            revert AuctionHasntCompleted();
        }
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;

        // Transfer the NFT from AuctionHouse to the winning bidder
        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        // Send the final bid amount to the escrow
        payable(auction.escrowAddress).transfer(auction.amount);

        // Log approximate affiliate share in the event (for reference)
        uint256 affiliateShare = (auction.amount * auction.affiliateFee) / 10000;

        emit AuctionEnded(
            _auctionId,
            address(this),
            auction.bidder,
            auction.affiliate,
            auction.amount,
            affiliateShare
        );
        
        // Remove auction from existence to free up storage
        delete auctions[_auctionId];
        delete auctionEncryptedMessages[_auctionId];
        delete auctionExists[_auctionId];
    }

    /**
     * @notice Cancel an auction if no bids have been placed and return NFT to the owner.
     * @param _auctionId The ID of the auction to cancel
     */
    function cancelAuction(uint256 _auctionId) external nonReentrant {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Only the auction owner can cancel
        require(msg.sender == auction.auctionOwner, "Only auction owner can cancel");
        
        if (auction.bidder != address(0)) {
            revert AuctionHasBid();
        }
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;

        // Return the NFT to the auctionOwner
        IERC721(auction.tokenContract).transferFrom(address(this), auction.auctionOwner, auction.tokenId);

        emit AuctionCanceled(
            _auctionId,
            address(this),
            auction.auctionOwner
        );
        
        // Remove auction from existence to free up storage
        delete auctions[_auctionId];
        delete auctionEncryptedMessages[_auctionId];
        delete auctionExists[_auctionId];
    }

    /**
     * @notice Once the auction is ended, the winning bidder can update their
     *         encrypted message using the seller's encryption key, if desired.
     * @param _auctionId The ID of the auction
     * @param _newMsg The new encrypted message
     */
    function setWinningBidderEncryptedMessage(
        uint256 _auctionId,
        EncryptedMessage calldata _newMsg
    ) external {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Check if auction is still active 
        if (block.timestamp < auction.startTime + auction.duration) {
            revert AuctionStillActive();
        }
        
        // Only the winning bidder can update
        if (auction.bidder != msg.sender) {
            revert NotWinner();
        }

        // Update the encrypted message
        auctionEncryptedMessages[_auctionId] = _newMsg;

        // Emit event with isFinal = true
        emit AuctionEncryptedMessage(
            _auctionId,
            address(this),
            msg.sender,
            _newMsg.encryptedData,
            _newMsg.ephemeralPublicKey,
            _newMsg.iv,
            _newMsg.verificationHash,
            true
        );
    }

    /**
     * @notice Allows the owner to rescue ERC20 tokens sent to this contract by mistake
     * @param tokenAddress The address of the ERC20 token to rescue
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to rescue
     */
    function rescueERC20(address tokenAddress, address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can rescue tokens");
        require(to != address(0), "Cannot rescue to zero address");
        
        // Create a generic ERC20 interface to call transfer
        IERC20 token = IERC20(tokenAddress);
        
        // Transfer the tokens to the specified address
        bool success = token.transfer(to, amount);
        require(success, "Token transfer failed");
        
        emit ERC20Rescued(tokenAddress, to, amount);
    }

    /**
     * @notice Allows the owner to rescue ETH sent to this contract by mistake
     * @param to The address to send the ETH to
     * @param amount The amount of ETH to rescue
     */
    function rescueETH(address payable to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can rescue ETH");
        require(to != address(0), "Cannot rescue to zero address");
        require(amount <= address(this).balance, "Insufficient ETH balance");
        
        // Transfer ETH to the specified address
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
        
        emit ETHRescued(to, amount);
    }

    /**
     * @notice Allows the owner to rescue an ERC721 token sent to this contract by mistake
     * @param tokenAddress The address of the ERC721 token to rescue
     * @param to The address to send the token to
     * @param tokenId The ID of the token to rescue
     */
    function rescueERC721(address tokenAddress, address to, uint256 tokenId) external {
        require(msg.sender == owner, "Only owner can rescue tokens");
        require(to != address(0), "Cannot rescue to zero address");
        
        // Make sure this token is not part of an active auction
        if (tokenToAuctionId[tokenAddress][tokenId] != 0) {
            require(!auctionExists[tokenToAuctionId[tokenAddress][tokenId]], "Cannot rescue token in active auction");
        }
        
        // Create a generic ERC721 interface to call transferFrom
        IERC721 token = IERC721(tokenAddress);
        
        // Transfer the token to the specified address
        token.transferFrom(address(this), to, tokenId);
        
        emit ERC721Rescued(tokenAddress, to, tokenId);
    }

    // Events for token rescues
    event ERC20Rescued(address indexed token, address indexed to, uint256 amount);
    event ETHRescued(address indexed to, uint256 amount);
    event ERC721Rescued(address indexed token, address indexed to, uint256 tokenId);
}