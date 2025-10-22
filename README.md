# KipuBank - Smart Contract Documentation

## 📋 Contract Description

KipuBank is a decentralized banking smart contract built on Ethereum that allows users to securely deposit and withdraw ETH with built-in security limits. The contract implements personal vaults for each user with automatic enforcement of withdrawal limits and total capacity restrictions.

### Key Features:
- **Personal Vaults**: Each user has an individual balance stored in mapping
- **Security Limits**: Maximum 1 ETH withdrawal per transaction (configurable)
- **Global Cap**: Total contract capacity of 5 ETH (configurable)
- **Real-time Tracking**: Monitors total deposits, withdrawals, and balances
- **Secure Operations**: Implements Checks-Effects-Interactions pattern and custom errors

## 🚀 Deployment Instructions

### Prerequisites:
- Ethereum wallet (MetaMask, etc.)
- Testnet ETH for gas fees (Sepolia recommended)
- Remix IDE or development environment

### Deployment Steps:

#### Using Remix IDE:
1. Open [Remix IDE](https://remix.ethereum.org)
2. Create new file `KipuBank.sol` and paste the contract code
3. Compile with Solidity version 0.8.20 or higher
4. Navigate to "Deploy & Run Transactions" tab
5. Select environment:
   - For testing: "JavaScript VM"
   - For production: "Injected Provider - MetaMask" (ensure you're on Sepolia testnet)
6. Set constructor parameters:
   - `_withdrawalThreshold`: 1000000000000000000 (1 ETH in wei)
   - `_bankCap`: 5000000000000000000 (5 ETH in wei)
7. Click "Transact" and confirm the transaction in your wallet
8. Copy the deployed contract address for future interactions

#### Using Hardhat/Truffle:
```bash
# Compile contract
npx hardhat compile

# Deploy to network
npx hardhat run scripts/deploy.js --network sepolia