// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title ISoundBondCurve
 * @notice Interface for SoundBondCurve contract
 */
interface ISoundBondCurve is IERC20 {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TokensPurchased(
        address indexed buyer,
        uint256 chzAmount,
        uint256 tokensReceived,
        uint256 newPrice
    );
    
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 chzReceived,
        uint256 exitFee,
        uint256 newPrice
    );
    
    event SlopeUpdated(uint256 oldAlpha, uint256 newAlpha, address indexed updatedBy);
    
    event BonusTokensMinted(uint256 amount, address indexed recipient);
    
    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Purchase tokens with CHZ
    /// @return tokensReceived Amount of tokens received
    function buy() external payable returns (uint256 tokensReceived);
    
    /// @notice Sell tokens for CHZ
    /// @param tokenAmount Amount of tokens to sell
    /// @return chzReceived Amount of CHZ received after fees
    function sell(uint256 tokenAmount) external returns (uint256 chzReceived);
    
    /// @notice Update bonding curve slope (only authorized router)
    /// @param deltaAlpha Amount to increase slope by
    function updateSlope(uint256 deltaAlpha) external;
    
    /// @notice Mint bonus tokens to club treasury (only authorized router)
    /// @param amount Amount of bonus tokens to mint
    function bonusMint(uint256 amount) external;
    
    /// @notice Calculate current token price
    /// @param supply Current token supply
    /// @return price Current price in CHZ wei
    function calculatePrice(uint256 supply) external view returns (uint256 price);
    
    /// @notice Calculate cost to buy specific amount of tokens
    /// @param tokenAmount Amount of tokens to buy
    /// @return cost Cost in CHZ wei
    function calculateBuyCost(uint256 tokenAmount) external view returns (uint256 cost);
    
    /// @notice Calculate CHZ received from selling tokens
    /// @param tokenAmount Amount of tokens to sell
    /// @return chzReceived CHZ received after fees
    function calculateSellReturn(uint256 tokenAmount) external view returns (uint256 chzReceived);
    
    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Current slope of the bonding curve
    function alpha() external view returns (uint256);
    
    /// @notice Base price of the bonding curve
    function beta() external view returns (uint256);
    
    /// @notice Exit fee in basis points
    function exitFeeBps() external view returns (uint256);
    
    /// @notice CHZ vault balance
    function vaultBalance() external view returns (uint256);
    
    /// @notice Club treasury address
    function clubTreasury() external view returns (address);
    
    /// @notice Total bonus tokens minted
    function totalBonusTokens() external view returns (uint256);
    
    /// @notice Authorized noise router
    function noiseRouter() external view returns (address);
} 