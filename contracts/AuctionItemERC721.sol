// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";

// Custom errors
error NotTokenOwnerOrApproved();
error TokenDoesNotExist();
error InvalidTokenURI();
error InvalidContractURI();
error InvalidTermsOfServiceURI();
error InvalidRoyaltyBasisPoints();
error InvalidRoyaltyRecipient();
error InvalidMetadata();
error MintingDisabled();

/**
 * @title AuctionItemERC721
 * @dev ERC721 token for auction items with UMP-compatible metadata
 */
contract AuctionItemERC721 is IERC4906, ERC721URIStorage, Ownable {
    using Strings for uint256;

    struct TokenMetadata {
        string name;
        string description;
        string image;
        string termsOfService;
        string[] supplementalImages;
    }

    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    string private _contractURI;
    uint256 private _nextTokenId;

    // Base URI for metadata
    string private _baseTokenURI;

    // Events for OpenSea compatibility
    event ContractURIUpdated(string newURI);
    event OwnershipChanged(address indexed previousOwner, address indexed newOwner);
    event TokenMetadataUpdated(
        uint256 indexed tokenId,
        string name,
        string description,
        string image,
        string termsOfService
    );

    constructor(string memory name_, string memory symbol_, string memory contractURI_) 
        ERC721(name_, symbol_) 
        Ownable(msg.sender) 
    {
        _contractURI = contractURI_;
        _nextTokenId = 1;
    }

    function mint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function mintWithMetadata(
        address to,
        string memory name,
        string memory description,
        string memory image,
        string memory termsOfService,
        string[] memory supplementalImages
    ) public onlyOwner returns (uint256) {
        uint256 tokenId = mint(to);
        setTokenMetadata(tokenId, name, description, image, termsOfService, supplementalImages);
        
        // Emit metadata update event for The Graph
        emit TokenMetadataUpdated(
            tokenId,
            name,
            description,
            image,
            termsOfService
        );
        
        return tokenId;
    }

    function setTokenMetadata(
        uint256 tokenId,
        string memory name,
        string memory description,
        string memory image,
        string memory termsOfService,
        string[] memory supplementalImages
    ) public onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        
        _tokenMetadata[tokenId] = TokenMetadata(
            name,
            description,
            image,
            termsOfService,
            supplementalImages
        );
        
        // Generate and set the token URI
        string memory tokenURI = generateTokenURI(tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        // Emit metadata update event for The Graph
        emit TokenMetadataUpdated(
            tokenId,
            name,
            description,
            image,
            termsOfService
        );
        
        // Also emit the ERC-4906 event for metadata update
        emit MetadataUpdate(tokenId);
    }

    function generateTokenURI(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        TokenMetadata memory metadata = _tokenMetadata[tokenId];
        
        string memory supplementalImagesJson = _generateSupplementalImagesJson(metadata.supplementalImages);
        
        string memory attributes = string(abi.encodePacked(
            '[{"trait_type":"Terms of Service","value":"', metadata.termsOfService, '"},',
            '{"trait_type":"Supplemental Images","value":', supplementalImagesJson, '}]'
        ));

        string memory json = Base64.encode(
            bytes(string(
                abi.encodePacked(
                    '{"name": "', metadata.name, '",',
                    '"description": "', metadata.description, '",',
                    '"image": "', metadata.image, '",',
                    '"attributes": ', attributes, '}'
                )
            ))
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function _generateSupplementalImagesJson(string[] memory images) internal pure returns (string memory) {
        if (images.length == 0) {
            return "[]";
        }

        string memory result = "[";
        for (uint256 i = 0; i < images.length; i++) {
            if (i > 0) {
                result = string(abi.encodePacked(result, ","));
            }
            result = string(abi.encodePacked(result, "\"", images[i], "\""));
        }
        result = string(abi.encodePacked(result, "]"));

        return result;
    }

    function getTokenMetadata(uint256 tokenId) public view returns (TokenMetadata memory) {
        require(_exists(tokenId), "Token does not exist");
        return _tokenMetadata[tokenId];
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory newURI) public onlyOwner {
        _contractURI = newURI;
    }

    function changeOwnership(address newOwner) public onlyOwner {
        address oldOwner = owner();
        _transferOwnership(newOwner);
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Sets the base URI for token metadata
     * @param baseURI New base URI
     */
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
        
        // Emit batch update for all tokens
        emit BatchMetadataUpdate(0, type(uint256).max);
    }
    
    /**
     * @dev Returns the base URI for token metadata
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}