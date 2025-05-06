// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "./AuctionHouse.sol";

contract AuctionHouseFactory {
    event AuctionHouseCreated(address indexed auctionHouse, address indexed owner);
    
    constructor() {}
    
    function createAuctionHouse(
        string memory _name,
        string memory _image,
        string memory _description,
        string memory _contractURI,
        string memory _symbol,
        uint256 _customDeadline,
        address _auctionItemFactory,
        address _escrowFactory
    ) external returns (address) {
        AuctionHouse newAuctionHouse = new AuctionHouse(
            _name,
            _image,
            _description,
            _contractURI,
            _symbol,
            _customDeadline,
            _auctionItemFactory,
            _escrowFactory
        );
        
        // Transfer ownership to the caller
        newAuctionHouse.transferOwnership(msg.sender);
        
        emit AuctionHouseCreated(address(newAuctionHouse), msg.sender);
        
        return address(newAuctionHouse);
    }
}
