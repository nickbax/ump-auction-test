// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAuctionHouse} from "./interfaces/IAuctionHouse.sol";
import {AffiliateEscrowFactory} from "./AffiliateEscrowFactory.sol";
import {AffiliateEscrow} from "./AffiliateEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AuctionItemERC721Factory} from "./AuctionItemERC721Factory.sol";
import {AuctionItemERC721} from "./AuctionItemERC721.sol";

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
error InsufficientTokenAmount();
error TokenTransferFailed();
error InsufficientFunds();
error OnlyOwnerCanRescue();
error CannotRescueToZeroAddress();
error CannotRescueWhileAuctionsActive();
error InsufficientBalance();
error TokenInActiveAuction();
error BidsAlreadyPlaced();
error BidTooLow();
error ReservePriceTooLow();

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
    uint256 highestBid;
    uint256 endTime;
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
    uint256 paymentAmount; 
}

contract AuctionHouse is IAuctionHouse, ReentrancyGuard, IERC721Receiver, Ownable {
    /// @notice A user-friendly name for this auction house.
    string public houseName;
    
    /// @notice An image URL for this auction house (e.g. IPFS link).
    string public image;
    
    /// @notice A text description for this auction house.
    string public description;

    /// @notice Versioning info
    string public constant VERSION = "0.0.5";
    
    /// @notice Settlement deadline in seconds after auction end
    uint256 public settlementDeadline = 21 days; // Default to 21 days

    // Counter for creating new auction IDs
    uint256 private nextAuctionId;

    // Auction data
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public auctionExists;
    mapping(uint256 => EncryptedMessage) public auctionEncryptedMessages;
    mapping(address => mapping(uint256 => uint256)) public tokenToAuctionId; // Maps token contract + tokenId to auctionId
    
    AuctionItemERC721 public auctionItemContract;
    
    AffiliateEscrowFactory public escrowFactory;
    
    // Counter for active auctions 
    uint256 public activeAuctionsCount;
    
    // Default address for the auction item factory
    address public auctionItemFactoryAddress;
    
    constructor(
        string memory _name,
        string memory _image,
        string memory _description,
        string memory _contractURI,
        string memory _symbol,
        uint256 _customDeadline,
        address _auctionItemFactory,
        address _escrowFactory
    ) Ownable(msg.sender) {
        houseName = _name;
        image = _image;
        description = _description;
        
        if (_customDeadline > 0) {
            settlementDeadline = _customDeadline;
        } else {
            settlementDeadline = 21 days;
        }
        
        // Store the factory address
        auctionItemFactoryAddress = _auctionItemFactory;
        
        // Create the AuctionItem contract directly
        AuctionItemERC721Factory factory = AuctionItemERC721Factory(_auctionItemFactory);
        auctionItemContract = AuctionItemERC721(factory.createAuctionItemERC721(
            string.concat(_name, " Items"),
            _symbol,
            _contractURI
        ));
        
        escrowFactory = AffiliateEscrowFactory(_escrowFactory);
        
        emit AuctionHouseMetadataUpdated(
            address(this),
            _name,
            _image,
            _description
        );
    }
    
    /**
     * @notice Creates a new NFT contract for this auction house
     * @param _name The name of the NFT collection
     * @param _symbol The symbol of the NFT collection
     * @param _contractURI The URI for the contract metadata
     * @return The address of the new NFT contract
     */
    function createNFTContract(
        string memory _name,
        string memory _symbol,
        string memory _contractURI
    ) public onlyOwner returns (address) {
        // Create a new NFT contract using the stored factory address
        AuctionItemERC721Factory factory = AuctionItemERC721Factory(auctionItemFactoryAddress);
        address nftContract = factory.createAuctionItemERC721(
            _name,
            _symbol,
            _contractURI
        );
        
        return nftContract;
    }

    // Define the NFT metadata struct
    struct NFTMetadata {
        string name;
        string description;
        string image;
        string termsOfService;
        string[] supplementalImages;
    }
    
    /**
     * @notice Implements the IERC721Receiver interface to allow this contract to receive ERC721 tokens
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        // accept the token
        emit NFTReceived(operator, from, msg.sender, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
    
    // Add a new event for tracking NFT receipts
    event NFTReceived(
        address indexed operator,
        address indexed from,
        address indexed tokenContract,
        uint256 tokenId
    );

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
    /// @notice Emitted when the auction house metadata is updated
    event AuctionHouseMetadataUpdated(
        address indexed auctionHouse,
        string name,
        string image,
        string description
    );

    /// @notice Emitted when the settlement deadline is updated
    event SettlementDeadlineUpdated(uint256 newDeadline);

    /// @notice Emitted when a bid is created
    event BidCreated(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed bidder,
        uint256 bidAmount,
        address affiliate,
        bytes encryptedData,
        bytes ephemeralPublicKey,
        bytes iv,
        bytes verificationHash,
        bool isFinal
    );

    /**
     * @notice Creates a new auction
     */
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
    ) public nonReentrant returns (uint256) {
        // Ensure reserve price is at least 1 wei
        if (_reservePrice < 1) {
            revert ReservePriceTooLow();
        }
        
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
        
        // Generate auction ID
        uint256 auctionId = nextAuctionId++;
        
        // Calculate initial bid amount
        // This ensures first bid must be at least reservePrice
        uint256 initialBid = 0;
        uint256 minIncrement = (_reservePrice * _minBidIncrementBps) / 10000;
        
        if (minIncrement < _reservePrice) {
            initialBid = _reservePrice - minIncrement;
        } else {
            // If minIncrement is >= reservePrice, set initialBid to 0
            // This ensures first bid must be at least reservePrice
            initialBid = 0;
        }
        
        // Create auction with calculated initialBid
        auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            highestBid: initialBid, // Set initial bid amount
            endTime: _startTime + _duration,
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
            timeExtension: _timeExtension,
            paymentAmount: 0
        });
        
        // Create a fresh escrow contract for this auction
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
        
        // Increment active auctions counter
        activeAuctionsCount++;
        
        return auctionId;
    }

    /**
     * @notice Mints a new NFT and creates an auction for it
     */
    function createAuctionWithNewNFT(
        NFTMetadata calldata _metadata,
        uint256 _startTime,
        uint256 _reservePrice,
        uint256 _duration,
        uint16 _affiliateFee,
        address _arbiterAddress,
        address _escrowFactoryAddress,
        address _auctionCurrency,
        bool _isPremiumAuction,
        uint16 _premiumRateBps,
        uint16 _minBidIncrementBps,
        uint256 _timeExtension
    ) external returns (uint256) {
        // Mint the NFT directly to this contract
        uint256 tokenId = auctionItemContract.mintWithMetadata(
            address(this),
            _metadata.name,
            _metadata.description,
            _metadata.image,
            _metadata.termsOfService,
            _metadata.supplementalImages
        );
        
        // Create the auction
        return createAuction(
            address(auctionItemContract),
            tokenId,
            _startTime,
            _reservePrice,
            _duration,
            _affiliateFee,
            _arbiterAddress,
            _escrowFactoryAddress,
            _auctionCurrency,
            _isPremiumAuction,
            _premiumRateBps,
            _minBidIncrementBps,
            _timeExtension
        );
    }
    
    /**
     * @notice Create a bid on an auction, optionally attaching an encrypted message.       
     */
    function createBid(
        uint256 _auctionId,
        address _affiliate,
        EncryptedMessage calldata _encryptedMsg,
        uint256 _bidAmount
    ) external payable nonReentrant {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Check if auction has started
        if (block.timestamp < auction.startTime) {
            revert AuctionHasntStarted();
        }
        
        // Check if auction has ended
        if (block.timestamp >= auction.endTime) {
            revert AuctionExpired();
        }
        
        // Get minimum bid required using the getMinimumBid function
        uint256 minBidRequired = this.getMinimumBid(_auctionId);
        
        // Check if bid meets minimum requirement
        if (_bidAmount < minBidRequired) {
            revert BidTooLow();
        }
        
        // Check if this is a native ETH auction or ERC20 auction
        bool isNativeAuction = auction.auctionCurrency == address(0);
        
        // For native ETH auctions, ensure sent value matches bid amount
        if (isNativeAuction) {
            if (msg.value != _bidAmount) {
                revert InsufficientTokenAmount();
            }
        } else {
            // For ERC20 auctions, ensure allowance and transfer
            IERC20 token = IERC20(auction.auctionCurrency);
            if (token.allowance(msg.sender, address(this)) < _bidAmount) {
                revert InsufficientTokenAmount();
            }
            
            // Transfer tokens from bidder to this contract
            bool success = token.transferFrom(msg.sender, address(this), _bidAmount);
            if (!success) {
                revert TokenTransferFailed();
            }
        }
        
        // Store the bid amount for clarity
        uint256 bidAmount = _bidAmount;
        
        // Refund the previous highest bidder (if any)
        if (auction.bidder != address(0)) {
            address payable previousBidder = auction.bidder;
            uint256 prevBidAmount = auction.highestBid;
            
            // Handle premium payment if applicable
            if (auction.isPremiumAuction && auction.premiumBps > 0) {
                // Calculate premium based on minimum bid increment
                uint256 minIncrement = (prevBidAmount * auction.minBidIncrementBps) / 10000;
                uint256 premium = (minIncrement * auction.premiumBps) / 10000;
                
                _refundBidder(
                    isNativeAuction,
                    auction.auctionCurrency,
                    previousBidder,
                    prevBidAmount + premium
                );
                
                // Emit premium paid event
                emit PremiumPaid(
                    _auctionId,
                    address(this),
                    previousBidder,
                    msg.sender,
                    prevBidAmount,
                    premium
                );
                
                // Calculate the payment amount (what will go to escrow)
                // This is the bid amount minus any premiums that have been paid
                auction.paymentAmount = bidAmount - premium;
            } else {
                // Standard refund without premium
                _refundBidder(
                    isNativeAuction,
                    auction.auctionCurrency,
                    previousBidder,
                    prevBidAmount
                );
                
                // No premium, so payment amount is the full bid amount
                auction.paymentAmount = bidAmount;
            }
        } else {
            // First bid, so payment amount is the full bid amount
            auction.paymentAmount = bidAmount;
        }
        
        // Update auction with new highest bid
        auction.highestBid = bidAmount;
        auction.bidder = payable(msg.sender);
        auction.affiliate = _affiliate;
        
        // Store only the most recent encrypted message
        auctionEncryptedMessages[_auctionId] = _encryptedMsg;
        
        // Extend auction if bid is placed near the end
        if (auction.timeExtension > 0) {
            uint256 timeRemaining = auction.endTime - block.timestamp;
            if (timeRemaining < auction.timeExtension) {
                auction.endTime = block.timestamp + auction.timeExtension;
                emit AuctionExtended(_auctionId, address(this), auction.endTime);
            }
        }
        
        // Emit bid created event
        emit BidCreated(
            _auctionId,
            address(this),
            msg.sender,
            bidAmount,
            _affiliate,
            _encryptedMsg.encryptedData,
            _encryptedMsg.ephemeralPublicKey,
            _encryptedMsg.iv,
            _encryptedMsg.verificationHash,
            false // Not final message
        );
        
        // Also emit the encrypted message event
        emit AuctionEncryptedMessage(
            _auctionId,
            address(this),
            msg.sender,
            _encryptedMsg.encryptedData,
            _encryptedMsg.ephemeralPublicKey,
            _encryptedMsg.iv,
            _encryptedMsg.verificationHash,
            false // Not final message
        );
    }

    /**
     * @notice Returns all data for an auction
     * @param _auctionId The ID of the auction
     * @return Complete auction data
     */
    function getAuctionData(uint256 _auctionId) external view returns (Auction memory) {
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        return auctions[_auctionId];
    }

    /**
     * @notice Checks if an auction is active
     * @param _auctionId The ID of the auction
     * @return bool True if the auction is active, false otherwise
     */
    function isAuctionActive(uint256 _auctionId) public view returns (bool) {
        if (!auctionExists[_auctionId]) {
            return false;
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Auction is active if it has started but not ended
        return (
            block.timestamp >= auction.startTime && 
            block.timestamp < auction.endTime
        );
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
        
        // Check if auction has ended using endTime
        if (block.timestamp < auction.endTime) {
            revert AuctionHasntCompleted();
        }
        
        // Ensure there was at least one bid
        if (auction.bidder == address(0)) {
            revert("No bids placed");
        }
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;

        // Initialize the escrow with payment information
        AffiliateEscrow escrow = AffiliateEscrow(payable(auction.escrowAddress));
        
        // Set the payer (winning bidder) and settlement deadline
        escrow.setPayer(auction.bidder, settlementDeadline);
        
        // Set the affiliate if one was used
        if (auction.affiliate != address(0)) {
            escrow.setAffiliate(auction.affiliate, auction.affiliateFee);
        }
        
        // Transfer the NFT directly to the winning bidder instead of the escrow
        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        // Send the payment amount to the escrow (not the highest bid)
        bool isNativeAuction = auction.auctionCurrency == address(0);
        
        if (isNativeAuction) {
            // For native ETH, send the payment amount for this auction
            (bool success, ) = auction.escrowAddress.call{value: auction.paymentAmount}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // For ERC20 auction, send the payment amount for this auction
            IERC20 token = IERC20(auction.auctionCurrency);
            bool success = token.transfer(auction.escrowAddress, auction.paymentAmount);
            if (!success) {
                revert TokenTransferFailed();
            }
        }

        // Calculate affiliate share for the event
        uint256 affiliateShare = (auction.paymentAmount * auction.affiliateFee) / 10000;

        emit AuctionEnded(
            _auctionId,
            address(this),
            auction.bidder,
            auction.affiliate,
            auction.paymentAmount,
            affiliateShare
        );
        
        // Decrement active auctions counter
        activeAuctionsCount--;
    }

    /**
     * @notice Cancel an auction if no bids have been placed and return NFT to the owner.
     */
    function cancelAuction(uint256 _auctionId) external nonReentrant {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // Only the auction owner can cancel
        if (msg.sender != auction.auctionOwner) {
            revert NotAuctionOwner();
        }
        
        // Can only cancel if no bids have been placed
        if (auction.bidder != address(0)) {
            revert BidsAlreadyPlaced();
        }
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;
        
        // Transfer NFT back to the owner
        IERC721(auction.tokenContract).transferFrom(address(this), auction.auctionOwner, auction.tokenId);
        
        // Emit auction cancelled event
        emit AuctionCancelled(_auctionId, address(this), auction.auctionOwner);
        
        // Mark auction as cancelled by setting endTime to 0
        auction.endTime = 0;
        
        // Decrement active auctions counter
        activeAuctionsCount--;
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
        if (block.timestamp < auction.startTime + auction.endTime) {
            revert AuctionStillActive();
        }
        
        // Only the winning bidder can update
        if (auction.bidder != msg.sender) {
            revert NotWinner();
        }

        // Update the encrypted message
        auctionEncryptedMessages[_auctionId] = _newMsg;

        // Emit event with isFinal = true
        _emitEncryptedMessageEvent(_auctionId, msg.sender, _newMsg, true);
    }

    /**
     * @notice Helper function to refund a bidder
     */
    function _refundBidder(
        bool _isNativeAuction,
        address _tokenAddress,
        address payable _bidder,
        uint256 _amount
    ) internal {
        if (_isNativeAuction) {
            // Native ETH refund
            (bool success, ) = _bidder.call{value: _amount}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // ERC20 token refund
            IERC20 token = IERC20(_tokenAddress);
            bool success = token.transfer(_bidder, _amount);
            if (!success) {
                revert TokenTransferFailed();
            }
        }
    }

    /**
     * @notice Helper function to emit encrypted message events
     */
    function _emitEncryptedMessageEvent(
        uint256 _auctionId,
        address _bidder,
        EncryptedMessage memory _message,
        bool _isFinal
    ) internal {
        emit AuctionEncryptedMessage(
            _auctionId,
            address(this),
            _bidder,
            _message.encryptedData,
            _message.ephemeralPublicKey,
            _message.iv,
            _message.verificationHash,
            _isFinal
        );
    }

    /**
     * @notice Checks if there are any active auctions
     * @return bool True if no active auctions exist, false otherwise
     */
    function noActiveAuctions() public view returns (bool) {
        return activeAuctionsCount == 0;
    }

    /**
     * @notice Allows the owner to rescue ERC20 tokens sent to this contract by mistake
     * @param tokenAddress The address of the ERC20 token to rescue
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to rescue
     */
    function rescueERC20(address tokenAddress, address to, uint256 amount) external {
        if (msg.sender != owner()) {
            revert OnlyOwnerCanRescue();
        }
        if (to == address(0)) {
            revert CannotRescueToZeroAddress();
        }
        if (!noActiveAuctions()) {
            revert CannotRescueWhileAuctionsActive();
        }
        
        // Create a generic ERC20 interface to call transfer
        IERC20 token = IERC20(tokenAddress);
        
        // Transfer the tokens to the specified address
        bool success = token.transfer(to, amount);
        if (!success) {
            revert TokenTransferFailed();
        }
        
        emit ERC20Rescued(tokenAddress, to, amount);
    }

    /**
     * @notice Allows the owner to rescue ETH sent to this contract by mistake
     * @param to The address to send the ETH to
     * @param amount The amount of ETH to rescue
     */
    function rescueETH(address payable to, uint256 amount) external {
        if (msg.sender != owner()) {
            revert OnlyOwnerCanRescue();
        }
        if (to == address(0)) {
            revert CannotRescueToZeroAddress();
        }
        if (amount > address(this).balance) {
            revert InsufficientBalance();
        }
        if (!noActiveAuctions()) {
            revert CannotRescueWhileAuctionsActive();
        }
        
        // Transfer ETH to the specified address
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
        
        emit ETHRescued(to, amount);
    }

    /**
     * @notice Allows the owner to rescue an ERC721 token sent to this contract by mistake
     * @param tokenAddress The address of the ERC721 token to rescue
     * @param to The address to send the token to
     * @param tokenId The ID of the token to rescue
     */
    function rescueERC721(address tokenAddress, address to, uint256 tokenId) external {
        if (msg.sender != owner()) {
            revert OnlyOwnerCanRescue();
        }
        if (to == address(0)) {
            revert CannotRescueToZeroAddress();
        }
        if (!noActiveAuctions()) {
            revert CannotRescueWhileAuctionsActive();
        }
        
        // Make sure this token is not part of an active auction
        if (tokenToAuctionId[tokenAddress][tokenId] != 0) {
            if (auctionExists[tokenToAuctionId[tokenAddress][tokenId]]) {
                revert TokenInActiveAuction();
            }
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

    /**
     * @notice Updates the auction house metadata (name, image, description)
     */
    function updateAuctionHouseMetadata(
        string memory _name,
        string memory _image,
        string memory _description
    ) external {
        // Only the owner can update metadata
        if (msg.sender != owner()) {
            revert("Not authorized");
        }
        
        houseName = _name;
        image = _image;
        description = _description;
        
        // Emit event for metadata update
        emit AuctionHouseMetadataUpdated(
            address(this),
            _name,
            _image,
            _description
        );
    }

    /**
     * @notice Update the settlement deadline for future auctions
     */
    function updateSettlementDeadline(uint256 _newDeadline) external onlyOwner {
        settlementDeadline = _newDeadline;
        emit SettlementDeadlineUpdated(_newDeadline);
    }

    /**
     * @notice Returns the minimum bid required for an auction
     * @param _auctionId The ID of the auction
     * @return The minimum bid amount required
     */
    function getMinimumBid(uint256 _auctionId) external view returns (uint256) {
        // Verify auction exists
        if (!auctionExists[_auctionId]) {
            revert AuctionNotFound();
        }
        
        Auction storage auction = auctions[_auctionId];
        
        // If no bids yet, return reserve price
        if (auction.bidder == address(0)) {
            return auction.reservePrice;
        }
        
        // Otherwise, calculate minimum bid based on current highest bid
        uint256 minBidRequired = auction.highestBid + ((auction.highestBid * auction.minBidIncrementBps) / 10000);
        return minBidRequired;
    }

    event AuctionCancelled(
        uint256 indexed auctionId,
        address indexed auctionHouse,
        address indexed owner
    );

    
    // Batch function to end expired auctions
    function batchEndExpiredAuctions(uint256[] calldata _auctionIds) external {
        for (uint256 i = 0; i < _auctionIds.length; i++) {
            uint256 auctionId = _auctionIds[i];
            
            // Skip if auction doesn't exist
            if (!auctionExists[auctionId]) {
                continue;
            }
            
            Auction storage auction = auctions[auctionId];
            
            // Skip if auction hasn't ended yet
            if (block.timestamp < auction.endTime) {
                continue;
            }
            
            // Skip if no bids were placed
            if (auction.bidder == address(0)) {
                continue;
            }
            
            // End the auction
            try this.endAuction(auctionId) {
                // Auction ended successfully
            } catch {
                // Auction couldn't be ended, continue to the next one
            }
        }
    }
}