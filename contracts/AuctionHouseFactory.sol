// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {AuctionHouse} from "./AuctionHouse.sol";
import {AuctionItemERC721Factory} from "./AuctionItemERC721Factory.sol";
import {AuctionItemERC721} from "./AuctionItemERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionHouseFactory is Ownable {
    event AuctionHouseCreated(address indexed auctionHouse, address indexed owner);
    
    AuctionItemERC721Factory public immutable auctionItemFactory;
    address public escrowFactory;
    
    constructor(address _auctionItemFactory, address _escrowFactory) Ownable(msg.sender) {
        auctionItemFactory = AuctionItemERC721Factory(_auctionItemFactory);
        escrowFactory = _escrowFactory;
    }
    
    function createAuctionHouse(
        string memory _name,
        string memory _image,
        string memory _description,
        uint256 _customDeadline,
        address _auctionItemFactory,
        address _escrowFactoryAddr
    ) public returns (address) {
        // Create the auction house
        AuctionHouse newAuctionHouse = new AuctionHouse(
            _name,
            _image,
            _description,
            _customDeadline,
            _auctionItemFactory,
            _escrowFactoryAddr
        );
        
        // Transfer ownership to the caller
        newAuctionHouse.transferOwnership(msg.sender);
        
        emit AuctionHouseCreated(address(newAuctionHouse), msg.sender);
        return address(newAuctionHouse);
    }
}
