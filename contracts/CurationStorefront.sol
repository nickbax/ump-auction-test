// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error ListingNotFound();
error InvalidStorefront();
error InvalidPaymentAddress();
error NotTokenOwner();
error NotCurator();
error CurationNotFound();
error BatchSizeInvalid();

interface IStorefront {
    function listings(uint256 tokenId) external view returns (
        uint256,  // tokenId
        uint256,  // price
        address,  // paymentToken
        uint256   // listingTime
    );
    function erc1155Token() external view returns (address);
}

interface IAffiliateStorefront {
    function listings(uint256 tokenId) external view returns (
        uint256,  // tokenId
        uint256,  // price
        address,  // paymentToken
        uint256,  // listingTime
        uint16    // affiliateFee
    );
    function erc1155Token() external view returns (address);
}

contract CurationStorefront is ERC721URIStorage, Ownable {
    string public constant VERSION = "0.0.3";
    uint8 public constant MAX_BATCH_SIZE = 20; //TODO: Figure out optimal max size

    struct CuratedListing {
        address storefrontAddress;  // Address of the original storefront
        uint256 tokenId;           // Original token ID from the storefront
        bool active;               // Whether this listing is currently active
    }

    struct Curation {
        string name;
        string description;
        mapping(uint256 => CuratedListing) listings;  // listingId => CuratedListing
        mapping(address => bool) curators;           // Address => is curator
        uint256 nextListingId;                      // Counter for listing IDs within this curation
        address paymentAddress;                     // Address that receives affiliate payments
    }

    // Mapping from curation token ID to Curation
    mapping(uint256 => Curation) public curations;
    uint256 private _nextCurationId = 1;

    event CurationCreated(
        uint256 indexed curationId,
        string name,
        string description,
        address paymentAddress
    );

    event ListingCurated(
        uint256 indexed curationId,
        uint256 indexed listingId,
        address indexed storefrontAddress,
        uint256 tokenId
    );

    event ListingUpdated(
        uint256 indexed curationId,
        uint256 indexed listingId,
        bool active
    );

    event PaymentAddressUpdated(
        uint256 indexed curationId,
        address indexed oldAddress, 
        address indexed newAddress
    );

    event CuratorAdded(
        uint256 indexed curationId,
        address indexed curator
    );

    event CuratorRemoved(
        uint256 indexed curationId,
        address indexed curator
    );

    event MetadataUpdated(uint256 indexed curationId, string newTokenURI);

    constructor() ERC721("UMP Curated Storefronts", "UMPCURATOR") Ownable(msg.sender) {}

    modifier onlyCurator(uint256 curationId) {
        if (!curations[curationId].curators[msg.sender] && msg.sender != ownerOf(curationId)) {
            revert NotCurator();
        }
        _;
    }

    function setCurationMetadata(
        uint256 curationId, 
        string calldata newTokenURI
    ) external onlyTokenOwner(curationId) 
    {
        _setTokenURI(curationId, newTokenURI);
        emit MetadataUpdated(curationId, newTokenURI);
    }

    modifier onlyTokenOwner(uint256 curationId) {
        if (msg.sender != ownerOf(curationId)) {
            revert NotTokenOwner();
        }
        _;
    }

    function createCuration(
        string calldata name,
        string calldata description,
        address paymentAddress,
        string calldata tokenURI
    ) external returns (uint256) {
        if (paymentAddress == address(0)) revert InvalidPaymentAddress();

        uint256 curationId = _nextCurationId++;
        
        // Initialize the curation
        Curation storage curation = curations[curationId];
        curation.name = name;
        curation.description = description;
        curation.paymentAddress = paymentAddress;
        curation.nextListingId = 1;
        
        // Make creator both owner and curator
        curation.curators[msg.sender] = true;

        // Mint the NFT to the creator
        _mint(msg.sender, curationId);
        _setTokenURI(curationId, tokenURI);

        emit CurationCreated(curationId, name, description, paymentAddress);
        emit CuratorAdded(curationId, msg.sender);
        return curationId;
    }

    function addCurator(uint256 curationId, address curator) external onlyTokenOwner(curationId) {
        curations[curationId].curators[curator] = true;
        emit CuratorAdded(curationId, curator);
    }

    function removeCurator(uint256 curationId, address curator) external onlyTokenOwner(curationId) {
        curations[curationId].curators[curator] = false;
        emit CuratorRemoved(curationId, curator);
    }

    function isCurator(uint256 curationId, address curator) external view returns (bool) {
        return curations[curationId].curators[curator] || curator == ownerOf(curationId);
    }

    function setPaymentAddress(uint256 curationId, address newPaymentAddress) external onlyTokenOwner(curationId) {
        if (newPaymentAddress == address(0)) revert InvalidPaymentAddress();

        Curation storage curation = curations[curationId];
        address oldAddress = curation.paymentAddress;
        curation.paymentAddress = newPaymentAddress;
        
        emit PaymentAddressUpdated(curationId, oldAddress, newPaymentAddress);
    }

    function curateListing(
        uint256 curationId,
        address storefrontAddress,
        uint256 tokenId
    ) external onlyCurator(curationId) returns (uint256) {
        if (storefrontAddress == address(0)) revert InvalidStorefront();
        
        // Ensure the storefront exists and has the listing
        IStorefront storefront = IStorefront(storefrontAddress);
        (uint256 listedTokenId,,,) = storefront.listings(tokenId);
        if (listedTokenId == 0) revert ListingNotFound();

        Curation storage curation = curations[curationId];
        uint256 listingId = curation.nextListingId++;

        curation.listings[listingId] = CuratedListing({
            storefrontAddress: storefrontAddress,
            tokenId: tokenId,
            active: true
        });

        emit ListingCurated(curationId, listingId, storefrontAddress, tokenId);
        return listingId;
    }

    function updateListing(
        uint256 curationId,
        uint256 listingId,
        bool active
    ) external onlyCurator(curationId) {
        Curation storage curation = curations[curationId];
        CuratedListing storage listing = curation.listings[listingId];
        if (listing.storefrontAddress == address(0)) revert ListingNotFound();
        
        listing.active = active;
        emit ListingUpdated(curationId, listingId, active);
    }

        /**
     * @notice Struct for batch listing input to make function parameters cleaner
     * @dev This struct represents a single listing to be added to a curation
     */
    struct BatchListingInput {
        address storefrontAddress;
        uint256 tokenId;
    }


        /**
     * @notice Batch curate multiple listings from different storefronts
     * @param curationId The ID of the curation
     * @param listingsToAdd Array of BatchListingInput structs containing storefront addresses and token IDs
     * @return listingIds Array of the newly created listing IDs
     */
    function batchCurateListings(
        uint256 curationId,
        BatchListingInput[] calldata listingsToAdd
    ) external onlyCurator(curationId) returns (uint256[] memory) {
        if (listingsToAdd.length == 0 || listingsToAdd.length > MAX_BATCH_SIZE) revert BatchSizeInvalid();
        
        Curation storage curation = curations[curationId];
        uint256[] memory listingIds = new uint256[](listingsToAdd.length);
        address[] memory storefrontAddresses = new address[](listingsToAdd.length);
        uint256[] memory tokenIds = new uint256[](listingsToAdd.length);
        
        // Validate all listings exist before making any changes
        for (uint256 i = 0; i < listingsToAdd.length; i++) {
            BatchListingInput calldata input = listingsToAdd[i];
            
            if (input.storefrontAddress == address(0)) revert InvalidStorefront();
            
            // Verify the listing exists in the storefront
            IStorefront storefront = IStorefront(input.storefrontAddress);
            (uint256 listedTokenId,,,) = storefront.listings(input.tokenId);
            if (listedTokenId == 0) revert ListingNotFound();
            
            // Store for event emission
            storefrontAddresses[i] = input.storefrontAddress;
            tokenIds[i] = input.tokenId;
        }
        
        // Add all listings after validation
        for (uint256 i = 0; i < listingsToAdd.length; i++) {
            uint256 listingId = curation.nextListingId++;
            listingIds[i] = listingId;
            
            BatchListingInput calldata input = listingsToAdd[i];
            curation.listings[listingId] = CuratedListing({
                storefrontAddress: input.storefrontAddress,
                tokenId: input.tokenId,
                active: true
            });
            
            // Emit individual event for each listing added
            emit ListingCurated(curationId, listingId, input.storefrontAddress, input.tokenId);
        }
        
        return listingIds;
    }
    /**
     * @notice Batch update the active state of multiple listings
     * @param curationId The ID of the curation
     * @param listingIds Array of listing IDs to update
     * @param activeStates Array of active states to set (must match listingIds length)
     */
    function batchUpdateListings(
        uint256 curationId,
        uint256[] calldata listingIds,
        bool[] calldata activeStates
    ) external onlyCurator(curationId) {
        if (listingIds.length == 0) revert BatchSizeInvalid();
        if (listingIds.length > MAX_BATCH_SIZE) revert BatchSizeInvalid();
        if (listingIds.length != activeStates.length) revert("Length mismatch");
        
        Curation storage curation = curations[curationId];
        
        for (uint256 i = 0; i < listingIds.length; i++) {
            uint256 listingId = listingIds[i];
            CuratedListing storage listing = curation.listings[listingId];
            if (listing.storefrontAddress == address(0)) revert ListingNotFound();
            
            bool newActiveState = activeStates[i];
            listing.active = newActiveState;
            
            // Emit individual event for each update
            emit ListingUpdated(curationId, listingId, newActiveState);
        }
    }

    function getCurationDetails(uint256 curationId) external view returns (
        string memory name,
        string memory description,
        address paymentAddress,
        address owner,
        uint256 totalListings
    ) {
        if (curationId >= _nextCurationId) revert CurationNotFound();
        
        Curation storage curation = curations[curationId];
        return (
            curation.name,
            curation.description,
            curation.paymentAddress,
            ownerOf(curationId),
            curation.nextListingId - 1
        );
    }

    function getCuratedListing(
        uint256 curationId,
        uint256 listingId
    ) external view returns (
        address storefrontAddress,
        uint256 tokenId,
        bool active,
        uint256 price,
        address paymentToken,
        uint16 affiliateFee,
        address erc1155Token
    ) {
        Curation storage curation = curations[curationId];
        CuratedListing memory listing = curation.listings[listingId];
        if (listing.storefrontAddress == address(0)) revert ListingNotFound();

        // Get the ERC1155 token address
        address _erc1155Token = IStorefront(listing.storefrontAddress).erc1155Token();

        // Try to get affiliate fee if it's an affiliate storefront
        try IAffiliateStorefront(listing.storefrontAddress).listings(listing.tokenId) returns (
            uint256 _tokenId,
            uint256 _price,
            address _paymentToken,
            uint256,
            uint16 _affiliateFee
        ) {
            return (
                listing.storefrontAddress,
                listing.tokenId,
                listing.active,
                _price,
                _paymentToken,
                _affiliateFee,
                _erc1155Token
            );
        } catch {
            // If it's not an affiliate storefront, get regular listing info
            (,uint256 _price, address _paymentToken,) = IStorefront(listing.storefrontAddress).listings(listing.tokenId);
            return (
                listing.storefrontAddress,
                listing.tokenId,
                listing.active,
                _price,
                _paymentToken,
                0,
                _erc1155Token
            );
        }
    }

    function getListingERC1155Token(
        uint256 curationId,
        uint256 listingId
    ) external view returns (address) {
        Curation storage curation = curations[curationId];
        CuratedListing memory listing = curation.listings[listingId];
        if (listing.storefrontAddress == address(0)) revert ListingNotFound();
        
        return IStorefront(listing.storefrontAddress).erc1155Token();
    }
}