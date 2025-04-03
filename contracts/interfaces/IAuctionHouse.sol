// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

interface IAuctionHouse {
    struct EncryptedMessage {
        bytes encryptedData;
        bytes ephemeralPublicKey;
        bytes iv;
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

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed auctionOwner,
        address tokenContract,
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice,
        uint16 affiliateFee,
        address arbiter,
        address escrowAddress,
        bool isPremiumAuction
    );

    event AuctionBid(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed bidder,
        address affiliate,
        uint256 amount,
        bool firstBid
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed winner,
        address affiliate,
        uint256 finalAmount,
        uint256 affiliatePayout
    );

    event AuctionCanceled(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed auctionOwner
    );

    function createBid(
        uint256 _auctionId,
        address _affiliate,
        EncryptedMessage calldata _encryptedMsg
    ) external payable;
    
    function endAuction(uint256 _auctionId) external;
    function cancelAuction(uint256 _auctionId) external;
}