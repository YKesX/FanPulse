// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {ISoundBondCurve} from "./interfaces/ISoundBondCurve.sol";
import {IEnergyOracle} from "./interfaces/IEnergyOracle.sol";

/**
 * @title NoiseRouter
 * @author FanPulse Team
 * @notice Routes EnergyEvents to appropriate bonding curves and handles bonus minting
 * @dev Subscribes to EnergyOracle events and updates bonding curve slopes and bonus tokens
 * @custom:version 1.0.0
 * @custom:security Implements pause functionality and parameter validation
 */
contract NoiseRouter is Ownable, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EnergyOracle contract address
    IEnergyOracle public immutable energyOracle;
    
    /// @notice Mapping of matchId to bonding curve address
    mapping(uint256 => address) public matchCurves;
    
    /// @notice Mapping of matchId to club treasury address
    mapping(uint256 => address) public matchTreasuries;
    
    /// @notice Slope increment per dB-second (kappa parameter)
    uint256 public kappa;
    
    /// @notice Baseline dB level for calculations
    uint256 public baselineDb;
    
    /// @notice Bonus token multiplier (gamma parameter)
    uint256 public gamma;
    
    /// @notice Maximum bonus tokens per event
    uint256 public maxBonusPerEvent;
    
    /// @notice Maximum slope increment per event
    uint256 public maxSlopeIncrement;
    
    /// @notice Total events processed
    uint256 public totalEventsProcessed;
    
    /// @notice Total bonus tokens minted
    uint256 public totalBonusTokensMinted;
    
    /// @notice Total slope increments applied
    uint256 public totalSlopeIncrementsApplied;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Scale factor for calculations (1e18)
    uint256 public constant SCALE_FACTOR = 1e18;
    
    /// @notice Minimum duration for event processing (1 second)
    uint256 public constant MIN_DURATION = 1000; // 1000ms = 1s
    
    /// @notice Maximum duration for event processing (1 hour)
    uint256 public constant MAX_DURATION = 3600000; // 1 hour in ms
    
    /// @notice Default kappa value (0.00001)
    uint256 public constant DEFAULT_KAPPA = 1e13; // 0.00001 * 1e18
    
    /// @notice Default gamma value (0.1)
    uint256 public constant DEFAULT_GAMMA = 1e17; // 0.1 * 1e18
    
    /// @notice Default baseline dB (45.00 dB)
    uint256 public constant DEFAULT_BASELINE_DB = 4500; // 45.00 dB (scaled by 100)
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when a new bonding curve is registered
    /// @param matchId The match identifier
    /// @param curveAddress The bonding curve contract address
    /// @param treasuryAddress The club treasury address
    event BondingCurveRegistered(
        uint256 indexed matchId,
        address indexed curveAddress,
        address indexed treasuryAddress
    );
    
    /// @notice Emitted when an energy event is processed
    /// @param matchId The match identifier
    /// @param db The dB level
    /// @param duration The duration in milliseconds
    /// @param slopeIncrement The slope increment applied
    /// @param bonusTokens The bonus tokens minted
    event EnergyEventProcessed(
        uint256 indexed matchId,
        uint256 db,
        uint256 duration,
        uint256 slopeIncrement,
        uint256 bonusTokens
    );
    
    /// @notice Emitted when parameters are updated
    /// @param param The parameter name
    /// @param oldValue The old value
    /// @param newValue The new value
    event ParameterUpdated(string param, uint256 oldValue, uint256 newValue);
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Thrown when curve is not registered for match
    error CurveNotRegistered();
    
    /// @notice Thrown when curve is already registered
    error CurveAlreadyRegistered();
    
    /// @notice Thrown when invalid parameters are provided
    error InvalidParameters();
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    
    /// @notice Thrown when unauthorized caller
    error Unauthorized();
    
    /// @notice Thrown when calculation overflow occurs
    error CalculationOverflow();
    
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Initialize the NoiseRouter
    /// @param energyOracle_ EnergyOracle contract address
    /// @param owner_ Contract owner address
    constructor(
        address energyOracle_,
        address owner_
    ) Ownable(owner_) {
        if (energyOracle_ == address(0)) revert ZeroAddress();
        
        energyOracle = IEnergyOracle(energyOracle_);
        
        // Set default parameters
        kappa = DEFAULT_KAPPA;
        gamma = DEFAULT_GAMMA;
        baselineDb = DEFAULT_BASELINE_DB;
        maxBonusPerEvent = 1000 * 1e18; // 1000 tokens max
        maxSlopeIncrement = 1e15; // 0.001 max slope increment
    }
    
    /*//////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Register a bonding curve for a match
    /// @param matchId The match identifier
    /// @param curveAddress The bonding curve contract address
    /// @param treasuryAddress The club treasury address
    function registerBondingCurve(
        uint256 matchId,
        address curveAddress,
        address treasuryAddress
    ) external onlyOwner {
        if (curveAddress == address(0)) revert ZeroAddress();
        if (treasuryAddress == address(0)) revert ZeroAddress();
        if (matchCurves[matchId] != address(0)) revert CurveAlreadyRegistered();
        
        matchCurves[matchId] = curveAddress;
        matchTreasuries[matchId] = treasuryAddress;
        
        emit BondingCurveRegistered(matchId, curveAddress, treasuryAddress);
    }
    
    /// @notice Process energy event and update bonding curve
    /// @param matchId The match identifier
    /// @param db The dB level (scaled by 100)
    /// @param duration The duration in milliseconds
    /// @param timestamp The event timestamp
    /// @param tier The event tier
    /// @dev This function is called by the EnergyOracle contract
    function processEnergyEvent(
        uint256 matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        string calldata tier
    ) external nonReentrant whenNotPaused {
        if (msg.sender != address(energyOracle)) revert Unauthorized();
        
        address curveAddress = matchCurves[matchId];
        if (curveAddress == address(0)) revert CurveNotRegistered();
        
        // Validate duration
        if (duration < MIN_DURATION || duration > MAX_DURATION) revert InvalidParameters();
        
        // Calculate slope increment (Δα = κ * (db - baseline) * duration / 5000)
        uint256 slopeIncrement = 0;
        if (db > baselineDb) {
            uint256 dbDelta = db - baselineDb;
            slopeIncrement = (kappa * dbDelta * duration) / 5000; // 5000ms = 5s reference
            
            // Cap slope increment
            if (slopeIncrement > maxSlopeIncrement) {
                slopeIncrement = maxSlopeIncrement;
            }
        }
        
        // Calculate bonus tokens (γ * (db - baseline) * duration / 5000)
        uint256 bonusTokens = 0;
        if (db > baselineDb) {
            uint256 dbDelta = db - baselineDb;
            bonusTokens = (gamma * dbDelta * duration) / 5000; // 5000ms = 5s reference
            
            // Cap bonus tokens
            if (bonusTokens > maxBonusPerEvent) {
                bonusTokens = maxBonusPerEvent;
            }
        }
        
        // Update bonding curve slope
        if (slopeIncrement > 0) {
            try ISoundBondCurve(curveAddress).updateSlope(slopeIncrement) {
                totalSlopeIncrementsApplied += slopeIncrement;
            } catch {
                // Log error but continue processing
                slopeIncrement = 0;
            }
        }
        
        // Mint bonus tokens to club treasury
        if (bonusTokens > 0) {
            try ISoundBondCurve(curveAddress).bonusMint(bonusTokens) {
                totalBonusTokensMinted += bonusTokens;
            } catch {
                // Log error but continue processing
                bonusTokens = 0;
            }
        }
        
        // Update counters
        totalEventsProcessed++;
        
        emit EnergyEventProcessed(matchId, db, duration, slopeIncrement, bonusTokens);
    }
    
    /// @notice Calculate slope increment for given parameters
    /// @param db The dB level
    /// @param duration The duration in milliseconds
    /// @return slopeIncrement The calculated slope increment
    function calculateSlopeIncrement(uint256 db, uint256 duration) external view returns (uint256 slopeIncrement) {
        if (db <= baselineDb) return 0;
        
        uint256 dbDelta = db - baselineDb;
        slopeIncrement = (kappa * dbDelta * duration) / 5000;
        
        if (slopeIncrement > maxSlopeIncrement) {
            slopeIncrement = maxSlopeIncrement;
        }
    }
    
    /// @notice Calculate bonus tokens for given parameters
    /// @param db The dB level
    /// @param duration The duration in milliseconds
    /// @return bonusTokens The calculated bonus tokens
    function calculateBonusTokens(uint256 db, uint256 duration) external view returns (uint256 bonusTokens) {
        if (db <= baselineDb) return 0;
        
        uint256 dbDelta = db - baselineDb;
        bonusTokens = (gamma * dbDelta * duration) / 5000;
        
        if (bonusTokens > maxBonusPerEvent) {
            bonusTokens = maxBonusPerEvent;
        }
    }
    
    /// @notice Get bonding curve address for a match
    /// @param matchId The match identifier
    /// @return curveAddress The bonding curve address
    function getBondingCurve(uint256 matchId) external view returns (address curveAddress) {
        return matchCurves[matchId];
    }
    
    /// @notice Get club treasury address for a match
    /// @param matchId The match identifier
    /// @return treasuryAddress The club treasury address
    function getClubTreasury(uint256 matchId) external view returns (address treasuryAddress) {
        return matchTreasuries[matchId];
    }
    
    /// @notice Get processing statistics
    /// @return totalEvents Total events processed
    /// @return totalBonusTokens Total bonus tokens minted
    /// @return totalSlopeIncrements Total slope increments applied
    function getStats() external view returns (
        uint256 totalEvents,
        uint256 totalBonusTokens,
        uint256 totalSlopeIncrements
    ) {
        return (totalEventsProcessed, totalBonusTokensMinted, totalSlopeIncrementsApplied);
    }
    
    /*//////////////////////////////////////////////////////////////
                                ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Set kappa parameter
    /// @param newKappa New kappa value
    function setKappa(uint256 newKappa) external onlyOwner {
        if (newKappa == 0) revert InvalidParameters();
        
        uint256 oldKappa = kappa;
        kappa = newKappa;
        
        emit ParameterUpdated("kappa", oldKappa, newKappa);
    }
    
    /// @notice Set gamma parameter
    /// @param newGamma New gamma value
    function setGamma(uint256 newGamma) external onlyOwner {
        if (newGamma == 0) revert InvalidParameters();
        
        uint256 oldGamma = gamma;
        gamma = newGamma;
        
        emit ParameterUpdated("gamma", oldGamma, newGamma);
    }
    
    /// @notice Set baseline dB
    /// @param newBaselineDb New baseline dB value
    function setBaselineDb(uint256 newBaselineDb) external onlyOwner {
        if (newBaselineDb == 0) revert InvalidParameters();
        
        uint256 oldBaselineDb = baselineDb;
        baselineDb = newBaselineDb;
        
        emit ParameterUpdated("baselineDb", oldBaselineDb, newBaselineDb);
    }
    
    /// @notice Set maximum bonus tokens per event
    /// @param newMaxBonus New maximum bonus tokens
    function setMaxBonusPerEvent(uint256 newMaxBonus) external onlyOwner {
        if (newMaxBonus == 0) revert InvalidParameters();
        
        uint256 oldMaxBonus = maxBonusPerEvent;
        maxBonusPerEvent = newMaxBonus;
        
        emit ParameterUpdated("maxBonusPerEvent", oldMaxBonus, newMaxBonus);
    }
    
    /// @notice Set maximum slope increment per event
    /// @param newMaxSlopeIncrement New maximum slope increment
    function setMaxSlopeIncrement(uint256 newMaxSlopeIncrement) external onlyOwner {
        if (newMaxSlopeIncrement == 0) revert InvalidParameters();
        
        uint256 oldMaxSlopeIncrement = maxSlopeIncrement;
        maxSlopeIncrement = newMaxSlopeIncrement;
        
        emit ParameterUpdated("maxSlopeIncrement", oldMaxSlopeIncrement, newMaxSlopeIncrement);
    }
    
    /// @notice Update bonding curve for a match
    /// @param matchId The match identifier
    /// @param newCurveAddress New bonding curve address
    /// @param newTreasuryAddress New club treasury address
    function updateBondingCurve(
        uint256 matchId,
        address newCurveAddress,
        address newTreasuryAddress
    ) external onlyOwner {
        if (newCurveAddress == address(0)) revert ZeroAddress();
        if (newTreasuryAddress == address(0)) revert ZeroAddress();
        if (matchCurves[matchId] == address(0)) revert CurveNotRegistered();
        
        matchCurves[matchId] = newCurveAddress;
        matchTreasuries[matchId] = newTreasuryAddress;
        
        emit BondingCurveRegistered(matchId, newCurveAddress, newTreasuryAddress);
    }
    
    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }
    
    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Emergency function to process events manually
    /// @param matchId The match identifier
    /// @param db The dB level
    /// @param duration The duration
    function emergencyProcessEvent(
        uint256 matchId,
        uint256 db,
        uint256 duration
    ) external onlyOwner {
        processEnergyEvent(matchId, db, duration, block.timestamp, "manual");
    }
} 