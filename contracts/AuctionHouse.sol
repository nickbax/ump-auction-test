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
    string public constant VERSION = "0.0.4";
    
    /// @notice Settlement deadline in seconds after auction end
    uint256 public settlementDeadline = 21 days; // Default to 21 days

    // Counter for creating new auction IDs
    uint256 private nextAuctionId;

    // Auction data
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public auctionExists;
    mapping(uint256 => EncryptedMessage) public auctionEncryptedMessages;
    mapping(address => mapping(uint256 => uint256)) public tokenToAuctionId; // Maps token contract + tokenId to auctionId
    
    AuctionItemERC721Factory public immutable auctionItemFactory;
    
    // Mapping to track NFT contracts created by this auction house
    mapping(string => address) public nftContracts;
    
    AffiliateEscrowFactory public escrowFactory;
    
    constructor(
        string memory _name,
        string memory _image,
        string memory _description,
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
        
        auctionItemFactory = AuctionItemERC721Factory(_auctionItemFactory);
        escrowFactory = AffiliateEscrowFactory(_escrowFactory);
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
        // Create a new NFT contract using the factory
        address nftContract = auctionItemFactory.createAuctionItemERC721(
            _name,
            _symbol,
            _contractURI
        );
        
        // Store the contract address
        nftContracts[_symbol] = nftContract;
        
        // The factory already transfers ownership to the caller (this contract)
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
        
        // Calculate initial amount to be reservePrice - minBidIncrement
        // This ensures first bid must be at least reservePrice
        uint256 initialBid = 0;
        if (_reservePrice > 0) {
            uint256 minIncrement = (_reservePrice * _minBidIncrementBps) / 10000; 
            if (minIncrement < _reservePrice) {
                initialBid = _reservePrice - minIncrement;
            }
        }
        
        // Create a new auction
        auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            highestBid: initialBid,
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
        
        return auctionId;
    }

    /**
     * @notice Mints a new NFT and creates an auction for it
     */
    function createAuctionWithNewNFT(
        address _nftContract,
        NFTMetadata memory _metadata,
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
    ) public returns (uint256) {
        // Mint the NFT directly to this contract
        AuctionItemERC721 nft = AuctionItemERC721(_nftContract);
        uint256 tokenId = nft.mintWithMetadata(
            address(this),
            _metadata.name,
            _metadata.description,
            _metadata.image,
            _metadata.termsOfService,
            _metadata.supplementalImages
        );
        
        // Create the auction
        return createAuction(
            _nftContract,
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
        if (block.timestamp >= auction.startTime + auction.duration) {
            revert AuctionExpired();
        }
        
        // Check if bid meets reserve price
        if (_bidAmount < auction.reservePrice) {
            revert BidBelowReservePrice();
        }
        
        // Check if bid increment is sufficient
        uint256 minBidRequired = auction.highestBid + ((auction.highestBid * auction.minBidIncrementBps) / 10000);
        if (_bidAmount < minBidRequired) {
            revert BidIncrementTooLow();
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
            } else {
                // Standard refund without premium
                _refundBidder(
                    isNativeAuction,
                    auction.auctionCurrency,
                    previousBidder,
                    prevBidAmount
                );
            }
        }
        
        // Calculate the payment amount (what will go to escrow)
        // This is the bid amount minus any premiums that have been paid
        auction.paymentAmount = bidAmount;
        
        // Update auction state
        auction.highestBid = bidAmount;
        auction.bidder = payable(msg.sender);
        
        // Update affiliate if provided
        if (_affiliate != address(0)) {
            auction.affiliate = _affiliate;
        }
        
        // Store encrypted message if provided
        if (_encryptedMsg.encryptedData.length > 0) {
            auctionEncryptedMessages[_auctionId] = _encryptedMsg;
            _emitEncryptedMessageEvent(_auctionId, msg.sender, _encryptedMsg, false);
        }
        
        // Check if we need to extend the auction
        uint256 timeRemaining = (auction.startTime + auction.duration) - block.timestamp;
        if (timeRemaining < auction.timeExtension) {
            // Extend the auction by the time extension amount
            auction.duration += auction.timeExtension;
            
            // Emit auction extended event
            emit AuctionExtended(
                _auctionId,
                address(this),
                auction.startTime + auction.duration
            );
        }
        
        // Emit bid event
        emit AuctionBid(
            _auctionId,
            address(this),
            msg.sender,
            auction.affiliate,
            bidAmount,
            auction.bidder == payable(msg.sender) // firstBid flag
        );
    }

    /**
     * @notice End an auction, finalizing the sale and forwarding funds to escrow.
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
        
        // Ensure there was at least one bid
        if (auction.bidder == address(0)) {
            revert("No bids placed");
        }
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;

        // Set affiliate and payer on the escrow contract for this auction
        AffiliateEscrow escrow = AffiliateEscrow(payable(auction.escrowAddress));
        if (auction.affiliate != address(0)) {
            escrow.setAffiliate(auction.affiliate, auction.affiliateFee);
        }
        escrow.setPayer(auction.bidder, settlementDeadline);

        // Transfer the NFT directly to the winning bidder instead of the escrow
        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        // Send the final bid amount to the escrow
        bool isNativeAuction = auction.auctionCurrency == address(0);
        
        if (isNativeAuction) {
            // For native ETH, use the actual contract balance
            uint256 contractBalance = address(this).balance;
            
            (bool success, ) = auction.escrowAddress.call{value: contractBalance}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // ERC20 auction
            IERC20 token = IERC20(auction.auctionCurrency);
            uint256 tokenBalance = token.balanceOf(address(this));
            
            bool success = token.transfer(auction.escrowAddress, tokenBalance);
            if (!success) {
                revert TokenTransferFailed();
            }
        }

        emit AuctionEnded(
            _auctionId,
            address(this),
            auction.bidder,
            auction.affiliate,
            auction.highestBid,
            0 // affiliate payout, if you want to track it
        );
        
        // Remove auction from existence to free up storage
        delete auctions[_auctionId];
        delete auctionEncryptedMessages[_auctionId];
        delete auctionExists[_auctionId];
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
        require(msg.sender == auction.auctionOwner, "Not auction owner");
        
        // Can only cancel if no bids have been placed
        require(auction.bidder == address(0), "Bids already placed");
        
        // Clear token auction mapping
        tokenToAuctionId[auction.tokenContract][auction.tokenId] = 0;
        
        // Transfer NFT back to the owner
        IERC721(auction.tokenContract).transferFrom(address(this), auction.auctionOwner, auction.tokenId);
        
        // Emit auction cancelled event
        emit AuctionCancelled(_auctionId, address(this), auction.auctionOwner);
        
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
        // Start from auction ID 1 (since we start nextAuctionId at 1)
        for (uint256 i = 1; i < nextAuctionId; i++) {
            // Skip if this auction doesn't exist (might have been ended or cancelled)
            if (!auctionExists[i]) {
                continue;
            }
            
            Auction storage auction = auctions[i];
            
            // Check if auction is active (has started but not ended)
            if (block.timestamp >= auction.startTime && 
                block.timestamp < auction.startTime + auction.duration) {
                return false;
            }
        }
        
        return true;
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
}