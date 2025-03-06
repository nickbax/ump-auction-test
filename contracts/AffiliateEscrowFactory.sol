// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {AffiliateEscrow} from "./AffiliateEscrow.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

// Core errors - same as AffiliateEscrow
error InvalidAddress();
error InvalidState();

contract AffiliateEscrowFactory {
    using Clones for address;

    address public immutable escrowImplementation;
    
    event AffiliateEscrowCreated(
        address indexed escrowAddress,
        address indexed payee,
        address indexed storefront,
        address arbiter
    );

    constructor() {
        // Deploy the implementation contract
        escrowImplementation = address(new AffiliateEscrow());
        if (escrowImplementation == address(0)) {
            revert InvalidAddress();
        }
    }

    function createEscrow(
        address payee,
        address storefront, 
        address arbiter
    ) external returns (address) {
        // Create minimal proxy clone
        address payable clonedEscrow = payable(escrowImplementation.clone());
        if (clonedEscrow == address(0)) {
            revert InvalidAddress();
        }
        
        // Initialize the clone with the desired parameters
        AffiliateEscrow(clonedEscrow).initialize(
            payee,
            storefront,
            arbiter
        );
        
        emit AffiliateEscrowCreated(
            clonedEscrow,
            payee,
            storefront,
            arbiter
        );

        return clonedEscrow;
    }
}