// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IEnergyOracle
 * @notice Interface for EnergyOracle contract
 */
interface IEnergyOracle {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event EnergyEvent(
        uint256 indexed matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        string tier
    );
    
    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update oracle with new energy event
    /// @param matchId The match/session identifier
    /// @param db The peak dB level (scaled by 100)
    /// @param duration The event duration in milliseconds
    /// @param timestamp The event timestamp
    /// @param signature The sponsor's signature
    function update(
        uint256 matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        bytes calldata signature
    ) external;
    
    /// @notice Get last recorded event data
    /// @return lastDb The last recorded dB level
    /// @return lastTs The last recorded timestamp
    function getLastEvent() external view returns (uint16 lastDb, uint32 lastTs);
    
    /// @notice Check if cooldown is active
    /// @return active True if cooldown is active
    function isCooldownActive() external view returns (bool active);
    
    /// @notice Calculate tier for a given dB level
    /// @param db The dB level (scaled by 100)
    /// @return tier The calculated tier
    function calculateTier(uint256 db) external pure returns (string memory tier);
    
    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Sponsor address authorized to submit events
    function SPONSOR() external view returns (address);
    
    /// @notice EIP-712 domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    
    /// @notice Cooldown period in seconds
    function COOLDOWN_SECONDS() external view returns (uint32);
    
    /// @notice Maximum dB delta allowed
    function MAX_DB_DELTA() external view returns (uint16);
    
    /// @notice Contract version
    function VERSION() external view returns (string memory);
} 