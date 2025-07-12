// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/**
 * @title SoundBondCurve
 * @author FanPulse Team
 * @notice Linear bonding curve for sound-powered fan tokens with dynamic slope adjustment
 * @dev Implements P = α * S + β formula where P=price, S=supply, α=slope, β=base price
 * @custom:version 1.0.0
 * @custom:security Gas-optimized with reentrancy protection and access control
 */
contract SoundBondCurve is ERC20, ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Current slope of the bonding curve (α)
    uint256 public alpha;
    
    /// @notice Base price of the bonding curve (β) in CHZ wei
    uint256 public beta;
    
    /// @notice Exit fee in basis points (e.g., 200 = 2%)
    uint256 public exitFeeBps;
    
    /// @notice CHZ vault for curve liquidity
    uint256 public vaultBalance;
    
    /// @notice Club treasury address for fees and bonus tokens
    address public clubTreasury;
    
    /// @notice Total tokens minted as bonuses to club
    uint256 public totalBonusTokens;
    
    /// @notice Authorized noise router contract
    address public noiseRouter;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    /// @notice Maximum exit fee (5% = 500 bps)
    uint256 public constant MAX_EXIT_FEE_BPS = 500;
    
    /// @notice Scale factor for price calculations (1e18)
    uint256 public constant SCALE_FACTOR = 1e18;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when tokens are purchased
    /// @param buyer The address that bought tokens
    /// @param chzAmount The amount of CHZ spent
    /// @param tokensReceived The amount of tokens received
    /// @param newPrice The new token price after purchase
    event TokensPurchased(
        address indexed buyer,
        uint256 chzAmount,
        uint256 tokensReceived,
        uint256 newPrice
    );
    
    /// @notice Emitted when tokens are sold
    /// @param seller The address that sold tokens
    /// @param tokenAmount The amount of tokens sold
    /// @param chzReceived The amount of CHZ received after fees
    /// @param exitFee The exit fee paid
    /// @param newPrice The new token price after sale
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 chzReceived,
        uint256 exitFee,
        uint256 newPrice
    );
    
    /// @notice Emitted when slope is updated
    /// @param oldAlpha Previous slope value
    /// @param newAlpha New slope value
    /// @param updatedBy Address that updated the slope
    event SlopeUpdated(uint256 oldAlpha, uint256 newAlpha, address indexed updatedBy);
    
    /// @notice Emitted when bonus tokens are minted
    /// @param amount Amount of bonus tokens minted
    /// @param recipient Address that received the bonus tokens
    event BonusTokensMinted(uint256 amount, address indexed recipient);
    
    /// @notice Emitted when vault balance is updated
    /// @param oldBalance Previous vault balance
    /// @param newBalance New vault balance
    event VaultBalanceUpdated(uint256 oldBalance, uint256 newBalance);
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Thrown when insufficient CHZ is sent
    error InsufficientCHZ();
    
    /// @notice Thrown when insufficient tokens for operation
    error InsufficientTokens();
    
    /// @notice Thrown when insufficient vault balance
    error InsufficientVaultBalance();
    
    /// @notice Thrown when invalid parameters are provided
    error InvalidParameters();
    
    /// @notice Thrown when unauthorized address tries restricted operation
    error Unauthorized();
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    
    /// @notice Thrown when zero amount is provided
    error ZeroAmount();
    
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Initialize the bonding curve
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param alpha_ Initial slope value
    /// @param beta_ Base price in CHZ wei
    /// @param exitFeeBps_ Exit fee in basis points
    /// @param clubTreasury_ Club treasury address
    /// @param owner_ Contract owner address
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 alpha_,
        uint256 beta_,
        uint256 exitFeeBps_,
        address clubTreasury_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        if (alpha_ == 0) revert InvalidParameters();
        if (exitFeeBps_ > MAX_EXIT_FEE_BPS) revert InvalidParameters();
        if (clubTreasury_ == address(0)) revert ZeroAddress();
        
        alpha = alpha_;
        beta = beta_;
        exitFeeBps = exitFeeBps_;
        clubTreasury = clubTreasury_;
    }
    
    /*//////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Purchase tokens with CHZ
    /// @dev Implements P = α * S + β formula
    /// @return tokensReceived Amount of tokens received
    function buy() external payable nonReentrant returns (uint256 tokensReceived) {
        if (msg.value == 0) revert ZeroAmount();
        
        uint256 currentSupply = totalSupply();
        uint256 chzAmount = msg.value;
        
        // Calculate tokens to mint using quadratic formula
        // Given: P = α * S + β and CHZ = ∫P dS = (α/2) * S² + β * S
        // Solve for new supply: S_new = (-β + √(β² + 2αCHZ)) / α
        
        uint256 currentPrice = calculatePrice(currentSupply);
        uint256 discriminant = beta * beta + 2 * alpha * chzAmount;
        uint256 sqrtDiscriminant = sqrt(discriminant);
        
        // Calculate new supply
        uint256 newSupply;
        if (sqrtDiscriminant > beta) {
            newSupply = (sqrtDiscriminant - beta) * SCALE_FACTOR / alpha;
        } else {
            // Fallback to linear approximation for small amounts
            newSupply = currentSupply + (chzAmount * SCALE_FACTOR) / currentPrice;
        }
        
        tokensReceived = newSupply - currentSupply;
        if (tokensReceived == 0) revert InsufficientCHZ();
        
        // Update vault balance
        vaultBalance += chzAmount;
        
        // Mint tokens to buyer
        _mint(msg.sender, tokensReceived);
        
        // Calculate new price
        uint256 newPrice = calculatePrice(totalSupply());
        
        emit TokensPurchased(msg.sender, chzAmount, tokensReceived, newPrice);
        emit VaultBalanceUpdated(vaultBalance - chzAmount, vaultBalance);
    }
    
    /// @notice Sell tokens for CHZ
    /// @param tokenAmount Amount of tokens to sell
    /// @return chzReceived Amount of CHZ received after fees
    function sell(uint256 tokenAmount) external nonReentrant returns (uint256 chzReceived) {
        if (tokenAmount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < tokenAmount) revert InsufficientTokens();
        
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply - tokenAmount;
        
        // Calculate CHZ to return using integral formula
        // CHZ = ∫(α * S + β) dS from newSupply to currentSupply
        uint256 chzFromCurve = ((alpha * (currentSupply * currentSupply - newSupply * newSupply)) / (2 * SCALE_FACTOR)) 
                              + (beta * tokenAmount) / SCALE_FACTOR;
        
        if (chzFromCurve > vaultBalance) revert InsufficientVaultBalance();
        
        // Calculate exit fee
        uint256 exitFee = (chzFromCurve * exitFeeBps) / BPS_DENOMINATOR;
        chzReceived = chzFromCurve - exitFee;
        
        // Update vault balance
        vaultBalance -= chzFromCurve;
        
        // Burn tokens
        _burn(msg.sender, tokenAmount);
        
        // Send CHZ to seller
        (bool success, ) = msg.sender.call{value: chzReceived}("");
        if (!success) revert();
        
        // Send exit fee to club treasury
        if (exitFee > 0) {
            (bool feeSuccess, ) = clubTreasury.call{value: exitFee}("");
            if (!feeSuccess) revert();
        }
        
        // Calculate new price
        uint256 newPrice = calculatePrice(totalSupply());
        
        emit TokensSold(msg.sender, tokenAmount, chzReceived, exitFee, newPrice);
        emit VaultBalanceUpdated(vaultBalance + chzFromCurve, vaultBalance);
    }
    
    /// @notice Update bonding curve slope (only authorized router)
    /// @param deltaAlpha Amount to increase slope by
    function updateSlope(uint256 deltaAlpha) external {
        if (msg.sender != noiseRouter) revert Unauthorized();
        if (deltaAlpha == 0) revert ZeroAmount();
        
        uint256 oldAlpha = alpha;
        alpha += deltaAlpha;
        
        emit SlopeUpdated(oldAlpha, alpha, msg.sender);
    }
    
    /// @notice Mint bonus tokens to club treasury (only authorized router)
    /// @param amount Amount of bonus tokens to mint
    function bonusMint(uint256 amount) external {
        if (msg.sender != noiseRouter) revert Unauthorized();
        if (amount == 0) revert ZeroAmount();
        
        totalBonusTokens += amount;
        _mint(clubTreasury, amount);
        
        emit BonusTokensMinted(amount, clubTreasury);
    }
    
    /// @notice Calculate current token price
    /// @param supply Current token supply
    /// @return price Current price in CHZ wei
    function calculatePrice(uint256 supply) public view returns (uint256 price) {
        return (alpha * supply) / SCALE_FACTOR + beta;
    }
    
    /// @notice Calculate cost to buy specific amount of tokens
    /// @param tokenAmount Amount of tokens to buy
    /// @return cost Cost in CHZ wei
    function calculateBuyCost(uint256 tokenAmount) external view returns (uint256 cost) {
        if (tokenAmount == 0) return 0;
        
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply + tokenAmount;
        
        // Calculate using integral formula
        cost = ((alpha * (newSupply * newSupply - currentSupply * currentSupply)) / (2 * SCALE_FACTOR)) 
              + (beta * tokenAmount) / SCALE_FACTOR;
    }
    
    /// @notice Calculate CHZ received from selling tokens
    /// @param tokenAmount Amount of tokens to sell
    /// @return chzReceived CHZ received after fees
    function calculateSellReturn(uint256 tokenAmount) external view returns (uint256 chzReceived) {
        if (tokenAmount == 0) return 0;
        
        uint256 currentSupply = totalSupply();
        if (tokenAmount > currentSupply) return 0;
        
        uint256 newSupply = currentSupply - tokenAmount;
        
        // Calculate CHZ from curve
        uint256 chzFromCurve = ((alpha * (currentSupply * currentSupply - newSupply * newSupply)) / (2 * SCALE_FACTOR)) 
                              + (beta * tokenAmount) / SCALE_FACTOR;
        
        if (chzFromCurve > vaultBalance) return 0;
        
        // Subtract exit fee
        uint256 exitFee = (chzFromCurve * exitFeeBps) / BPS_DENOMINATOR;
        chzReceived = chzFromCurve - exitFee;
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
    
    /// @notice Set club treasury address (only owner)
    /// @param treasury_ New club treasury address
    function setClubTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        clubTreasury = treasury_;
    }
    
    /// @notice Set exit fee (only owner)
    /// @param newExitFeeBps_ New exit fee in basis points
    function setExitFee(uint256 newExitFeeBps_) external onlyOwner {
        if (newExitFeeBps_ > MAX_EXIT_FEE_BPS) revert InvalidParameters();
        exitFeeBps = newExitFeeBps_;
    }
    
    /// @notice Emergency withdraw from vault (only owner)
    /// @param amount Amount to withdraw
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        if (amount > vaultBalance) revert InsufficientVaultBalance();
        
        vaultBalance -= amount;
        (bool success, ) = owner().call{value: amount}("");
        if (!success) revert();
        
        emit VaultBalanceUpdated(vaultBalance + amount, vaultBalance);
    }
    
    /*//////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Calculate square root using Babylonian method
    /// @param x Input value
    /// @return result Square root of x
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // Initial guess
        result = x;
        uint256 k = (x / 2) + 1;
        
        // Babylonian method
        while (k < result) {
            result = k;
            k = (x / k + k) / 2;
        }
    }
    
    /// @notice Allow contract to receive CHZ
    receive() external payable {
        vaultBalance += msg.value;
    }
} 