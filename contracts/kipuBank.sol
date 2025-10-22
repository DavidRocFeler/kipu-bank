// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title KipuBank - Banking contract with personal vaults
/// @author Your Name
/// @notice Allows users to deposit ETH in personal vaults with withdrawal limits
contract KipuBank {
    // ============ CUSTOM ERRORS ============
    error ExceedsBankCap();
    error ExceedsWithdrawalThreshold();
    error InsufficientBalance();
    error Unauthorized();
    error ZeroAmount();
    
    // ============ IMMUTABLES ============
    /// @notice Maximum withdrawal limit per transaction
    uint256 public immutable WITHDRAWAL_THRESHOLD;
    
    /// @notice Maximum total deposits in the bank
    uint256 public immutable BANK_CAP;
    
    // ============ STATE VARIABLES ============
    /// @notice Total contract balance
    uint256 public totalBalance;
    
    /// @notice Deposit counter
    uint256 public depositCount;
    
    /// @notice Withdrawal counter
    uint256 public withdrawalCount;
    
    // ============ MAPPINGS ============
    /// @notice Balances of each user
    mapping(address => uint256) public balances;
    
    // ============ EVENTS ============
    /// @notice Emitted when a user deposits
    event Deposited(address indexed user, uint256 amount, uint256 timestamp);
    
    /// @notice Emitted when a user withdraws
    event Withdrawn(address indexed user, uint256 amount, uint256 timestamp);
    
    // ============ MODIFIERS ============
    /// @notice Verifies that the amount is not zero
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }
    
    // ============ CONSTRUCTOR ============
    /// @notice Configures bank limits
    /// @param _withdrawalThreshold Maximum withdrawal limit per transaction
    /// @param _bankCap Maximum total deposits limit
    constructor(uint256 _withdrawalThreshold, uint256 _bankCap) {
        WITHDRAWAL_THRESHOLD = _withdrawalThreshold;
        BANK_CAP = _bankCap;
    }
    
    // ============ EXTERNAL PAYABLE FUNCTIONS ============
    /// @notice Allows users to deposit ETH into their personal vault
    /// @dev Verifies that bank cap is not exceeded
    function deposit() external payable nonZeroAmount(msg.value) {
        // CHECK: Verify bank limit
        if (totalBalance + msg.value > BANK_CAP) {
            revert ExceedsBankCap();
        }
        
        // EFFECTS: Update state first
        balances[msg.sender] += msg.value;
        totalBalance += msg.value;
        depositCount++;
        
        // INTERACTIONS: None in this case
        
        emit Deposited(msg.sender, msg.value, block.timestamp);
    }
    
    /// @notice Allows users to withdraw funds from their vault
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external nonZeroAmount(amount) {
        // CHECK: Security verifications
        if (amount > WITHDRAWAL_THRESHOLD) {
            revert ExceedsWithdrawalThreshold();
        }
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance();
        }
        
        // EFFECTS: Update state first
        balances[msg.sender] -= amount;
        totalBalance -= amount;
        withdrawalCount++;
        
        // INTERACTIONS: Transfer after state updates
        _safeTransfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount, block.timestamp);
    }
    
    // ============ PRIVATE FUNCTIONS ============
    /// @notice Performs secure ETH transfer
    /// @param to Destination address
    /// @param amount Amount to transfer
    function _safeTransfer(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    // ============ EXTERNAL VIEW FUNCTIONS ============
    /// @notice Gets user balance
    /// @param user User address
    /// @return User's balance
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /// @notice Gets bank statistics
    /// @return totalDeposits, totalWithdrawals, currentBalance
    function getBankStats() external view returns (uint256, uint256, uint256) {
        return (depositCount, withdrawalCount, totalBalance);
    }
    
    /// @notice Verifies if a withdrawal is within the limit
    /// @param amount Amount to verify
    /// @return true if within the limit
    function isWithinWithdrawalLimit(uint256 amount) external view returns (bool) {
        return amount <= WITHDRAWAL_THRESHOLD;
    }
}

