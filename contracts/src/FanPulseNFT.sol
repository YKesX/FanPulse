// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "openzeppelin-contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "openzeppelin-contracts/token/common/ERC2981.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/**
 * @title FanPulseNFT
 * @author FanPulse Team
 * @notice CAP-721 NFT contract with royalties and tier-based minting for FanPulse ecosystem
 * @dev Implements ERC721, ERC2981 (royalties), and tier-based supply caps
 * @custom:version 1.0.0
 * @custom:security Router-only mint control with supply caps and royalty support
 */
contract FanPulseNFT is ERC721, ERC721Enumerable, ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Base URI for token metadata
    string private _baseTokenURI;
    
    /// @notice Authorized noise router contract
    address public noiseRouter;
    
    /// @notice Current token ID counter
    uint256 private _tokenIdCounter;
    
    /// @notice Mapping of token ID to tier
    mapping(uint256 => string) public tokenTiers;
    
    /// @notice Mapping of tier to current supply
    mapping(string => uint256) public tierSupply;
    
    /// @notice Mapping of tier to maximum supply
    mapping(string => uint256) public tierMaxSupply;
    
    /// @notice Mapping of tier to royalty basis points
    mapping(string => uint256) public tierRoyalties;
    
    /// @notice Default royalty recipient
    address public defaultRoyaltyRecipient;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Maximum royalty percentage (10% = 1000 bps)
    uint256 public constant MAX_ROYALTY_BPS = 1000;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when an NFT is minted
    /// @param to The recipient address
    /// @param tokenId The token ID
    /// @param tier The tier of the NFT
    /// @param matchId The match ID associated with the NFT
    event NFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        string tier,
        uint256 matchId
    );
    
    /// @notice Emitted when base URI is updated
    /// @param newBaseURI The new base URI
    event BaseURIUpdated(string newBaseURI);
    
    /// @notice Emitted when tier supply cap is updated
    /// @param tier The tier name
    /// @param oldCap The old supply cap
    /// @param newCap The new supply cap
    event TierSupplyCapUpdated(string tier, uint256 oldCap, uint256 newCap);
    
    /// @notice Emitted when tier royalty is updated
    /// @param tier The tier name
    /// @param oldRoyalty The old royalty in bps
    /// @param newRoyalty The new royalty in bps
    event TierRoyaltyUpdated(string tier, uint256 oldRoyalty, uint256 newRoyalty);
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Thrown when trying to mint beyond tier supply cap
    error TierSupplyCapExceeded();
    
    /// @notice Thrown when unauthorized address tries restricted operation
    error Unauthorized();
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    
    /// @notice Thrown when invalid tier is provided
    error InvalidTier();
    
    /// @notice Thrown when invalid royalty percentage is provided
    error InvalidRoyaltyPercentage();
    
    /// @notice Thrown when invalid parameters are provided
    error InvalidParameters();
    
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Initialize the FanPulseNFT contract
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param baseURI_ Base URI for token metadata
    /// @param royaltyRecipient_ Default royalty recipient address
    /// @param owner_ Contract owner address
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address royaltyRecipient_,
        address owner_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        if (royaltyRecipient_ == address(0)) revert ZeroAddress();
        
        _baseTokenURI = baseURI_;
        defaultRoyaltyRecipient = royaltyRecipient_;
        _tokenIdCounter = 1; // Start token IDs at 1
        
        // Initialize tier supply caps from tasks-5.yml
        tierMaxSupply["bronze"] = 5000;
        tierMaxSupply["silver"] = 500;
        tierMaxSupply["gold"] = 50;
        tierMaxSupply["legendary"] = 3;
        
        // Initialize tier royalties from tasks-5.yml
        tierRoyalties["bronze"] = 500;  // 5%
        tierRoyalties["silver"] = 500;  // 5%
        tierRoyalties["gold"] = 500;    // 5%
        tierRoyalties["legendary"] = 1000; // 10%
    }
    
    /*//////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mint NFT to recipient (only authorized router)
    /// @param to The recipient address
    /// @param tier The tier of the NFT
    /// @param matchId The match ID associated with the NFT
    /// @return tokenId The minted token ID
    function mint(
        address to,
        string calldata tier,
        uint256 matchId
    ) external nonReentrant returns (uint256 tokenId) {
        if (msg.sender != noiseRouter) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (tierMaxSupply[tier] == 0) revert InvalidTier();
        
        // Check supply cap
        if (tierSupply[tier] >= tierMaxSupply[tier]) {
            revert TierSupplyCapExceeded();
        }
        
        // Get new token ID
        tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        // Update tier supply
        tierSupply[tier]++;
        
        // Store tier for token
        tokenTiers[tokenId] = tier;
        
        // Mint token
        _safeMint(to, tokenId);
        
        // Set royalty for this token
        _setTokenRoyalty(tokenId, defaultRoyaltyRecipient, tierRoyalties[tier]);
        
        emit NFTMinted(to, tokenId, tier, matchId);
    }
    
    /// @notice Batch mint NFTs to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param tiers Array of tiers corresponding to each recipient
    /// @param matchIds Array of match IDs corresponding to each recipient
    /// @return tokenIds Array of minted token IDs
    function batchMint(
        address[] calldata recipients,
        string[] calldata tiers,
        uint256[] calldata matchIds
    ) external nonReentrant returns (uint256[] memory tokenIds) {
        if (msg.sender != noiseRouter) revert Unauthorized();
        if (recipients.length != tiers.length || recipients.length != matchIds.length) {
            revert InvalidParameters();
        }
        
        tokenIds = new uint256[](recipients.length);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            tokenIds[i] = mint(recipients[i], tiers[i], matchIds[i]);
        }
    }
    
    /// @notice Get tier for a token
    /// @param tokenId The token ID
    /// @return tier The tier of the token
    function getTier(uint256 tokenId) external view returns (string memory tier) {
        if (!_exists(tokenId)) revert InvalidParameters();
        return tokenTiers[tokenId];
    }
    
    /// @notice Get remaining supply for a tier
    /// @param tier The tier name
    /// @return remaining The remaining supply
    function getRemainingSupply(string calldata tier) external view returns (uint256 remaining) {
        if (tierMaxSupply[tier] == 0) revert InvalidTier();
        return tierMaxSupply[tier] - tierSupply[tier];
    }
    
    /// @notice Get all tiers information
    /// @return tierNames Array of tier names
    /// @return currentSupplies Array of current supplies
    /// @return maxSupplies Array of maximum supplies
    /// @return royaltyBps Array of royalty basis points
    function getAllTiers() external view returns (
        string[] memory tierNames,
        uint256[] memory currentSupplies,
        uint256[] memory maxSupplies,
        uint256[] memory royaltyBps
    ) {
        tierNames = new string[](4);
        currentSupplies = new uint256[](4);
        maxSupplies = new uint256[](4);
        royaltyBps = new uint256[](4);
        
        tierNames[0] = "bronze";
        tierNames[1] = "silver";
        tierNames[2] = "gold";
        tierNames[3] = "legendary";
        
        for (uint256 i = 0; i < 4; i++) {
            currentSupplies[i] = tierSupply[tierNames[i]];
            maxSupplies[i] = tierMaxSupply[tierNames[i]];
            royaltyBps[i] = tierRoyalties[tierNames[i]];
        }
    }
    
    /// @notice Check if a tier exists
    /// @param tier The tier name
    /// @return exists True if tier exists
    function tierExists(string calldata tier) external view returns (bool exists) {
        return tierMaxSupply[tier] > 0;
    }
    
    /*//////////////////////////////////////////////////////////////
                                ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Set noise router address (only owner)
    /// @param router_ New noise router address
    function setNoiseRouter(address router_) external onlyOwner {
        if (router_ == address(0)) revert ZeroAddress();
        noiseRouter = router_;
    }
    
    /// @notice Set base URI (only owner)
    /// @param baseURI_ New base URI
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }
    
    /// @notice Set tier supply cap (only owner)
    /// @param tier The tier name
    /// @param newCap The new supply cap
    function setTierSupplyCap(string calldata tier, uint256 newCap) external onlyOwner {
        if (newCap == 0) revert InvalidParameters();
        if (newCap < tierSupply[tier]) revert InvalidParameters(); // Can't set below current supply
        
        uint256 oldCap = tierMaxSupply[tier];
        tierMaxSupply[tier] = newCap;
        
        emit TierSupplyCapUpdated(tier, oldCap, newCap);
    }
    
    /// @notice Set tier royalty (only owner)
    /// @param tier The tier name
    /// @param royaltyBps The royalty in basis points
    function setTierRoyalty(string calldata tier, uint256 royaltyBps) external onlyOwner {
        if (royaltyBps > MAX_ROYALTY_BPS) revert InvalidRoyaltyPercentage();
        if (tierMaxSupply[tier] == 0) revert InvalidTier();
        
        uint256 oldRoyalty = tierRoyalties[tier];
        tierRoyalties[tier] = royaltyBps;
        
        emit TierRoyaltyUpdated(tier, oldRoyalty, royaltyBps);
    }
    
    /// @notice Set default royalty recipient (only owner)
    /// @param recipient_ New default royalty recipient
    function setDefaultRoyaltyRecipient(address recipient_) external onlyOwner {
        if (recipient_ == address(0)) revert ZeroAddress();
        defaultRoyaltyRecipient = recipient_;
    }
    
    /// @notice Add new tier (only owner)
    /// @param tier The tier name
    /// @param maxSupply The maximum supply for this tier
    /// @param royaltyBps The royalty in basis points
    function addTier(
        string calldata tier,
        uint256 maxSupply,
        uint256 royaltyBps
    ) external onlyOwner {
        if (maxSupply == 0) revert InvalidParameters();
        if (royaltyBps > MAX_ROYALTY_BPS) revert InvalidRoyaltyPercentage();
        if (tierMaxSupply[tier] != 0) revert InvalidParameters(); // Tier already exists
        
        tierMaxSupply[tier] = maxSupply;
        tierRoyalties[tier] = royaltyBps;
        
        emit TierSupplyCapUpdated(tier, 0, maxSupply);
        emit TierRoyaltyUpdated(tier, 0, royaltyBps);
    }
    
    /*//////////////////////////////////////////////////////////////
                                OVERRIDES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Override tokenURI to use composable base URI
    /// @param tokenId The token ID
    /// @return uri The token URI
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory uri) {
        if (!_exists(tokenId)) revert InvalidParameters();
        
        string memory tier = tokenTiers[tokenId];
        string memory baseURI = _baseURI();
        
        if (bytes(baseURI).length == 0) {
            return "";
        }
        
        // Return baseURI + tier + "/" + tokenId + ".json"
        return string(abi.encodePacked(baseURI, tier, "/", tokenId.toString(), ".json"));
    }
    
    /// @notice Override _baseURI
    /// @return uri The base URI
    function _baseURI() internal view override returns (string memory uri) {
        return _baseTokenURI;
    }
    
    /// @notice Override _burn to handle URI storage
    /// @param tokenId The token ID to burn
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
        
        // Decrease tier supply
        string memory tier = tokenTiers[tokenId];
        if (tierSupply[tier] > 0) {
            tierSupply[tier]--;
        }
        
        // Clear tier mapping
        delete tokenTiers[tokenId];
    }
    
    /// @notice Override _beforeTokenTransfer for enumerable
    /// @param from From address
    /// @param to To address
    /// @param tokenId Token ID
    /// @param batchSize Batch size
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    /// @notice Override supportsInterface for multiple inheritance
    /// @param interfaceId The interface identifier
    /// @return supported True if interface is supported
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC2981) returns (bool supported) {
        return super.supportsInterface(interfaceId);
    }
} 