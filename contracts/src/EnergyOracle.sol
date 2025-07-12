// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title EnergyOracle
 * @author FanPulse Team
 * @notice Records signed noise events from FanPulse ESP32-S3 devices on Chiliz Spicy testnet
 * @dev Implements EIP-712 signature verification with packed storage optimization
 * @custom:version 1.0.0
 * @custom:security Gas-optimized with packed storage and custom errors
 */
contract EnergyOracle {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Packed storage slot for last event data
    /// @dev Packed as: lastDb (uint16) | lastTs (uint32) | reserved (208 bits)
    /// @custom:storage-location erc7201:fanpulse.storage.EnergyOracle
    struct PackedEventData {
        uint16 lastDb;      // Last recorded dB level (0-65535, supports -655.35 to 655.35 dB)
        uint32 lastTs;      // Last recorded timestamp (unix timestamp)
        uint208 reserved;   // Reserved for future use
    }
    
    /// @notice Packed event data storage
    PackedEventData private _packedData;
    
    /// @notice Sponsor address authorized to submit events
    address public immutable SPONSOR;
    
    /// @notice EIP-712 domain separator for signature verification
    bytes32 public immutable DOMAIN_SEPARATOR;
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Cooldown period between events (30 seconds)
    uint32 public constant COOLDOWN_SECONDS = 30;
    
    /// @notice Maximum dB delta allowed between consecutive events
    uint16 public constant MAX_DB_DELTA = 20_00; // 20.00 dB (scaled by 100)
    
    /// @notice EIP-712 type hash for FanPulse events
    bytes32 public constant FANPULSE_EVENT_TYPEHASH = keccak256(
        "FanPulseEvent(uint256 matchId,uint256 db,uint256 duration,uint256 timestamp)"
    );
    
    /// @notice Contract version for EIP-712
    string public constant VERSION = "1";
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when a new energy event is recorded
    /// @param matchId The match/session identifier
    /// @param db The peak dB level (scaled by 100)
    /// @param duration The event duration in milliseconds
    /// @param timestamp The event timestamp
    /// @param tier The calculated tier based on dB level
    event EnergyEvent(
        uint256 indexed matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        string tier
    );
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Thrown when signature verification fails
    error InvalidSignature();
    
    /// @notice Thrown when trying to submit event during cooldown period
    error CooldownActive();
    
    /// @notice Thrown when dB delta exceeds maximum allowed
    error DbDeltaTooLarge();
    
    /// @notice Thrown when event timestamp is invalid
    error InvalidTimestamp();
    
    /// @notice Thrown when dB level is invalid
    error InvalidDbLevel();
    
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Initialize the EnergyOracle contract
    /// @param sponsor The authorized sponsor address
    constructor(address sponsor) {
        if (sponsor == address(0)) revert InvalidSignature();
        
        SPONSOR = sponsor;
        
        // Initialize EIP-712 domain separator for Chiliz Spicy testnet (chainId: 88882)
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("FanPulse")),
                keccak256(bytes(VERSION)),
                88882, // Chiliz Spicy testnet chain ID
                address(this)
            )
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Update oracle with new energy event
    /// @param matchId The match/session identifier
    /// @param db The peak dB level (scaled by 100, e.g., 1850 = 18.50 dB)
    /// @param duration The event duration in milliseconds
    /// @param timestamp The event timestamp (unix timestamp)
    /// @param signature The sponsor's signature
    function update(
        uint256 matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        bytes calldata signature
    ) external {
        // Input validation
        if (timestamp == 0) revert InvalidTimestamp();
        if (db > type(uint16).max) revert InvalidDbLevel();
        if (timestamp > type(uint32).max) revert InvalidTimestamp();
        
        // Load packed data once
        PackedEventData memory data = _packedData;
        
        // Check cooldown period
        unchecked {
            if (data.lastTs != 0 && timestamp - data.lastTs < COOLDOWN_SECONDS) {
                revert CooldownActive();
            }
        }
        
        // Check dB delta if not first event
        if (data.lastDb != 0) {
            unchecked {
                uint16 currentDb = uint16(db);
                uint16 dbDelta = currentDb > data.lastDb 
                    ? currentDb - data.lastDb 
                    : data.lastDb - currentDb;
                
                if (dbDelta > MAX_DB_DELTA) {
                    revert DbDeltaTooLarge();
                }
            }
        }
        
        // Verify EIP-712 signature
        _verifySignature(matchId, db, duration, timestamp, signature);
        
        // Update packed storage
        _packedData = PackedEventData({
            lastDb: uint16(db),
            lastTs: uint32(timestamp),
            reserved: 0
        });
        
        // Determine tier based on dB level
        string memory tier = _calculateTier(db);
        
        // Emit event
        emit EnergyEvent(matchId, db, duration, timestamp, tier);
    }
    
    /// @notice Get last recorded event data
    /// @return lastDb The last recorded dB level
    /// @return lastTs The last recorded timestamp
    function getLastEvent() external view returns (uint16 lastDb, uint32 lastTs) {
        PackedEventData memory data = _packedData;
        return (data.lastDb, data.lastTs);
    }
    
    /// @notice Check if cooldown is active
    /// @return active True if cooldown is active
    function isCooldownActive() external view returns (bool active) {
        PackedEventData memory data = _packedData;
        if (data.lastTs == 0) return false;
        
        unchecked {
            return block.timestamp - data.lastTs < COOLDOWN_SECONDS;
        }
    }
    
    /// @notice Calculate tier for a given dB level
    /// @param db The dB level (scaled by 100)
    /// @return tier The calculated tier
    function calculateTier(uint256 db) external pure returns (string memory tier) {
        return _calculateTier(db);
    }
    
    /*//////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Verify EIP-712 signature
    /// @param matchId The match identifier
    /// @param db The dB level
    /// @param duration The duration
    /// @param timestamp The timestamp
    /// @param signature The signature to verify
    function _verifySignature(
        uint256 matchId,
        uint256 db,
        uint256 duration,
        uint256 timestamp,
        bytes calldata signature
    ) internal view {
        // Create EIP-712 hash
        bytes32 structHash = keccak256(
            abi.encode(
                FANPULSE_EVENT_TYPEHASH,
                matchId,
                db,
                duration,
                timestamp
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        
        // Recover signer
        address signer = _recoverSigner(hash, signature);
        
        // Verify signer is authorized sponsor
        if (signer != SPONSOR) revert InvalidSignature();
    }
    
    /// @notice Recover signer from signature
    /// @param hash The message hash
    /// @param signature The signature
    /// @return signer The recovered signer address
    function _recoverSigner(bytes32 hash, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        // Extract signature components
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        
        // Adjust v for Ethereum's signature format
        if (v < 27) v += 27;
        
        // Recover signer
        signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
    
    /// @notice Calculate tier based on dB level
    /// @param db The dB level (scaled by 100)
    /// @return tier The calculated tier
    function _calculateTier(uint256 db) internal pure returns (string memory tier) {
        // Tier thresholds (scaled by 100)
        // Bronze: >= 15.00 dB (1500)
        // Silver: >= 25.00 dB (2500)  
        // Gold: >= 35.00 dB (3500)
        
        if (db >= 3500) return "gold";
        if (db >= 2500) return "silver";
        if (db >= 1500) return "bronze";
        return "none";
    }
} 