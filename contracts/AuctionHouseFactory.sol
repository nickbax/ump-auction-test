// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

interface IAuctionHouseFactory {
    event AuctionHouseCreated(
        address indexed auctionHouse,
        address indexed owner,
        address indexed arbiter
    );

    function createAuctionHouse(
        address _arbiter,
        address _erc721Token,           // Which ERC-721 token is being auctioned?
        uint256 _tokenId,               // Token ID for that ERC-721
        uint256 _startPrice,            // Starting price for the auction
        uint256 _duration,              // Auction duration in seconds
        uint16 _affiliateFee            // Max possible affiliate fee in basis points
    ) external returns (address);
}