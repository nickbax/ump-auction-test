// SPDX-License-Identifier: GPL-3.0
// UmpMetadata v0.1.1
// This contract keeps track of metadata for the UMP frontend operated by Ump Labs Inc.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract UmpMetadata is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Version information
    string public constant VERSION = "0.1.2";
    
    address public affiliateEscrowFactory;
    address public affiliateStorefrontFactory;
    address public receiptERC1155Factory;
    address public curationStorefronts;
    address public affiliateVerifier;
    
    EnumerableSet.AddressSet private allowlistedStorefronts;
    EnumerableSet.AddressSet private supportedERC20Tokens;

    event AffiliateEscrowFactoryUpdated(address newFactory);
    event AffiliateStorefrontFactoryUpdated(address newFactory);
    event ReceiptERC1155FactoryUpdated(address newFactory);
    event CurationStorefrontsUpdated(address newStorefronts);
    event AffiliateVerifierUpdated(address newVerifier);
    event StorefrontAllowlisted(address storefront);
    event StorefrontRemovedFromAllowlist(address storefront);
    event ERC20TokenAdded(address token);
    event ERC20TokenRemoved(address token);

    constructor(
        address _affiliateEscrowFactory,
        address _affiliateStorefrontFactory,
        address _receiptERC1155Factory,
        address _curationStorefronts,
        address _affiliateVerifier,
        address initialOwner
    ) Ownable(initialOwner) {
        affiliateEscrowFactory = _affiliateEscrowFactory;
        affiliateStorefrontFactory = _affiliateStorefrontFactory;
        receiptERC1155Factory = _receiptERC1155Factory;
        curationStorefronts = _curationStorefronts;
        affiliateVerifier = _affiliateVerifier;
    }

    function setAffiliateEscrowFactory(address newFactory) external onlyOwner {
        affiliateEscrowFactory = newFactory;
        emit AffiliateEscrowFactoryUpdated(newFactory);
    }

    function setAffiliateStorefrontFactory(address newFactory) external onlyOwner {
        affiliateStorefrontFactory = newFactory;
        emit AffiliateStorefrontFactoryUpdated(newFactory);
    }

    function setReceiptERC1155Factory(address newFactory) external onlyOwner {
        receiptERC1155Factory = newFactory;
        emit ReceiptERC1155FactoryUpdated(newFactory);
    }

    function setCurationStorefronts(address newStorefronts) external onlyOwner {
        curationStorefronts = newStorefronts;
        emit CurationStorefrontsUpdated(newStorefronts);
    }

    function setAffiliateVerifier(address newVerifier) external onlyOwner {
        affiliateVerifier = newVerifier;
        emit AffiliateVerifierUpdated(newVerifier);
    }

    function changeOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        _transferOwnership(newOwner);
    }

    function addStorefrontToAllowlist(address storefront) external onlyOwner {
        if (allowlistedStorefronts.add(storefront)) {
            emit StorefrontAllowlisted(storefront);
        }
    }

    function removeStorefrontFromAllowlist(address storefront) external onlyOwner {
        if (allowlistedStorefronts.remove(storefront)) {
            emit StorefrontRemovedFromAllowlist(storefront);
        }
    }

    function isStorefrontAllowlisted(address storefront) public view returns (bool) {
        return allowlistedStorefronts.contains(storefront);
    }

    function getAllowlistedStorefrontsCount() public view returns (uint256) {
        return allowlistedStorefronts.length();
    }

    function getAllowlistedStorefront(uint256 index) public view returns (address) {
        return allowlistedStorefronts.at(index);
    }

    function getAllAllowlistedStorefronts() public view returns (address[] memory) {
        return allowlistedStorefronts.values();
    }

    function addSupportedERC20Token(address token) external onlyOwner {
        if (supportedERC20Tokens.add(token)) {
            emit ERC20TokenAdded(token);
        }
    }

    function removeSupportedERC20Token(address token) external onlyOwner {
        if (supportedERC20Tokens.remove(token)) {
            emit ERC20TokenRemoved(token);
        }
    }

    function isSupportedERC20Token(address token) public view returns (bool) {
        return supportedERC20Tokens.contains(token);
    }

    function getSupportedERC20TokensCount() public view returns (uint256) {
        return supportedERC20Tokens.length();
    }

    function getSupportedERC20Token(uint256 index) public view returns (address) {
        return supportedERC20Tokens.at(index);
    }

    function getAllSupportedERC20Tokens() public view returns (address[] memory) {
        return supportedERC20Tokens.values();
    }
} 