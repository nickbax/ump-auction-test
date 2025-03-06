// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {AffiliateERC1155Storefront} from "./AffiliateERC1155Storefront.sol";

contract AffiliateERC1155StorefrontFactory {
    event StorefrontCreated(
        address indexed storefront, 
        address indexed owner, 
        address erc1155Token, 
        address escrowFactory,
        address affiliateVerifier,
        string version
    );
    string public constant VERSION = "0.0.3";
    address public immutable SEAPORT;
    uint256 public immutable MIN_SETTLE_TIME;

    constructor(address _seaport, uint256 _minSettleTime) {
        SEAPORT = _seaport;
        MIN_SETTLE_TIME = _minSettleTime;
    }

    function createStorefront(
        address designatedArbiter,
        address erc1155Token,
        address escrowFactory,
        address affiliateVerifier,
        uint256 initialSettleDeadline
    ) public returns (address) {
        AffiliateERC1155Storefront newStorefront = new AffiliateERC1155Storefront(
            SEAPORT,
            designatedArbiter,
            escrowFactory,
            erc1155Token,
            affiliateVerifier,
            MIN_SETTLE_TIME,
            initialSettleDeadline
        );

        newStorefront.transferOwnership(msg.sender);
        newStorefront.initialize();
        emit StorefrontCreated(
            address(newStorefront), 
            msg.sender, 
            erc1155Token, 
            escrowFactory,
            affiliateVerifier,
            VERSION
        );
        
        return address(newStorefront);
    }
}