# 🏦 KipuBank Secure - Multi-Token Banking Smart Contract

## 📖 Overview

**KipuBank Secure** is an advanced smart contract that enables users to deposit and withdraw multiple ERC20 tokens and ETH, with limit systems, role-based access control, and Chainlink price oracle integration for real-time USD conversions.

---

## 🚀 Implemented Improvements

### 1. 🔐 Role-Based Access Control  
**Purpose:** Enterprise security and scalable management

```solidity
- ADMIN_ROLE: Full system management
- OPERATOR_ROLE: Daily operations and token support
- RISK_MANAGER_ROLE: Risk parameter and limit configuration
```

---

### 2. 💰 Multi-Token Support  
**Purpose:** Flexibility and adaptability to different assets

```solidity
- Native support for ETH and any ERC20 token
- Per-token configuration (limits, capacity)
- Automatic handling of different decimals
```

---

### 3. 🛡️ Advanced Security Mechanisms  
**Purpose:** Protection against common attack vectors

```solidity
- SafeERC20 for non-standard tokens (USDT, etc.)
- ReentrancyGuard on all critical functions
- Emergency pause mechanism
- Validation of stale or deviated prices
```

---

### 4. 📊 Smart Limit System  
**Purpose:** Risk control and compliance

```solidity
- Per-transaction limits (per token)
- Daily USD limits (per user)
- Bank capacity limits (per token)
- Automatic USD conversion via Chainlink
```

---

### 5. 🔗 Chainlink Oracle Integration  
**Purpose:** Reliable and manipulation-resistant pricing

```solidity
- Price freshness validation (max 12 hours)
- Price deviation control (configurable per token)
- Secure fallback when price unavailable
```

---

## 🚀 Deployment Instructions

### Prerequisites
```bash
npm install @openzeppelin/contracts
npm install @chainlink/contracts
```

### Deployment Example
```solidity
// Example addresses (Mainnet)
address admin = 0xYourAdminAddress;
address ethUsdPriceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD

// Constructor parameters
constructor(admin, ethUsdPriceFeed);
```

### Initial Configuration
```javascript
// 1. Configure supported tokens
await bank.supportToken(
    usdcAddress,            // token
    ethers.utils.parseUnits("1000", 6),  // withdrawalLimit
    ethers.utils.parseUnits("5000", 6),  // depositLimit  
    ethers.utils.parseUnits("100000", 6), // bankCap
    "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6", // USDC/USD PriceFeed
    500 // 5% deviation threshold
);

// 2. Assign additional roles
await bank.grantRole(OPERATOR_ROLE, operatorAddress);
await bank.grantRole(RISK_MANAGER_ROLE, riskManagerAddress);
```

---

## 💻 Contract Interaction

### For Users
```javascript
// Deposit ETH
await bank.depositETH({ value: ethers.utils.parseEther("1.0") });

// Deposit Tokens
await usdc.approve(bank.address, amount);
await bank.depositToken(usdcAddress, amount);

// Withdraw funds
await bank.withdrawETH(amount);
await bank.withdrawToken(usdcAddress, amount);
```

### For Admins
```javascript
// Manage tokens
await bank.supportToken(...);
await bank.updatePriceFeed(token, newPriceFeed);

// Emergency actions
await bank.emergencyPause();
await bank.emergencyWithdraw(token, recipient);

// Queries
const balance = await bank.getBalance(user, token);
const usdValue = await bank.getUSDValue(token, amount);
```

---

## 🎯 Design Decisions & Trade-offs

### 1. Limit Architecture
**Decision:** Daily USD limits vs token amounts  
**Trade-off:**  
✅ Better volatility risk control  
❌ Added complexity due to price oracle dependency  

### 2. Price Handling
**Decision:** On-chain Chainlink prices  
**Trade-off:**  
✅ Decentralized, reliable data  
❌ Higher gas cost and external dependency  

### 3. Security vs Usability
**Decision:** Multi-layered security model  
**Trade-off:**  
✅ Strong protection against attacks  
❌ Slightly higher user complexity  

### 4. Token Flexibility
**Decision:** Support for any ERC20 token  
**Trade-off:**  
✅ Maximum interoperability  
❌ Potential malicious tokens (mitigated via implicit whitelist)  

---

## 🔧 Recommended Security Configurations

### Suggested Limits
```solidity
// ETH
withdrawalLimit: 10 ETH
depositLimit: 50 ETH  
bankCap: 1000 ETH

// Stablecoins (USDC, USDT)
withdrawalLimit: $10,000
depositLimit: $50,000
bankCap: $1,000,000

// Volatile Tokens
withdrawalLimit: $5,000
depositLimit: $25,000
bankCap: $500,000
```

### Price Thresholds
```solidity
priceDeviationThreshold: 500    // 5% for stable tokens
priceDeviationThreshold: 1000   // 10% for volatile tokens
PRICE_STALE_THRESHOLD: 12 hours // Balance between freshness and availability
```

---

## 📈 Production Considerations

### Recommended Monitoring
- Alerts when nearing 80% of capacity limits  
- Health monitoring of Chainlink price feeds  
- Suspicious activity tracking (multiple small txs)  

### Future Improvements
- Token whitelist implementation  
- Configurable fee system  
- Support for rebase/elastic tokens  
- DEX integration for liquidity  

---

## 🐛 Common Troubleshooting

**Error:** `"Transfer failed"`  
✅ Check contract allowance  
✅ Confirm token follows ERC20 standard  

**Error:** `"Stale price"`  
✅ Verify Chainlink feed activity  
✅ Adjust `PRICE_STALE_THRESHOLD` if necessary  

**Error:** `"Exceeds daily limit"`  
✅ Wait until next UTC day  
✅ Contact admin for limit adjustments  

---

**Version:** 2.0  
**Last Update:** November 2025
