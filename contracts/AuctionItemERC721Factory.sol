// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {AuctionItemERC721} from "./AuctionItemERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionItemERC721Factory is Ownable {
    event AuctionItemERC721Created(address indexed tokenContract, address indexed owner);

    constructor() Ownable(msg.sender) {}

    function createAuctionItemERC721(
        string memory name,
        string memory symbol,
        string memory contractURI
    ) public returns (address) {
        AuctionItemERC721 newToken = new AuctionItemERC721(name, symbol, contractURI);
        newToken.transferOwnership(msg.sender);
        
        emit AuctionItemERC721Created(address(newToken), msg.sender);
        return address(newToken);
    }
}