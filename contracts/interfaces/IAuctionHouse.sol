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
        uint256 firstBidTime;
        uint256 reservePrice;
        uint16 affiliateFee;
        address auctionOwner;
        address payable bidder;
        address affiliate;
        address arbiter;
        address escrow;
        address auctionCurrency;
    }

    event AuctionCreated(
        address indexed auctionAddress,
        address indexed auctionOwner,
        address indexed erc721Token,
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice,
        uint16 affiliateFee,
        address arbiter
    );

    event AuctionBid(
        address indexed auctionAddress,
        address indexed bidder,
        address indexed affiliate,
        uint256 amount,
        bool firstBid
    );

    event AuctionEnded(
        address indexed auctionAddress,
        address indexed winner,
        address indexed affiliate,
        uint256 finalAmount,
        uint256 affiliatePayout
    );

    event AuctionCanceled(
        address indexed auctionAddress,
        address indexed auctionOwner
    );

    function createBid(address _affiliate, EncryptedMessage calldata _encryptedMsg) external payable;
    function endAuction() external;
    function cancelAuction() external;
}