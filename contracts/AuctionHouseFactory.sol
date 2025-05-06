// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "./AuctionHouse.sol";

contract AuctionHouseFactory {
    // Updated event with more metadata
    event AuctionHouseCreated(
        address indexed auctionHouse, 
        address indexed owner,
        string name,
        string image,
        string description,
        string contractURI,
        string symbol,
        uint256 settlementDeadline
    );
    
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
        
        // Emit event with all metadata
        emit AuctionHouseCreated(
            address(newAuctionHouse), 
            msg.sender,
            _name,
            _image,
            _description,
            _contractURI,
            _symbol,
            _customDeadline
        );
        
        return address(newAuctionHouse);
    }
}
