# Deployment Guide for Tortoise v0.3

## Setting Up Your Keystore

### 1. Import Your Private Key to Keystore

First, import your private key into an encrypted keystore:

```bash
cast wallet import tortoise-deployer --interactive
```

This will:
- Prompt you to enter your private key (paste it without the 0x prefix)
- Ask you to create a password for the keystore
- Save the encrypted key to `~/.foundry/keystores/tortoise-deployer`

**Security Tips:**
- Use a dedicated deployment wallet, not your main wallet
- Only fund it with enough ETH for deployment + gas
- Use a strong password for the keystore
- Never share your keystore password

### 2. Configure Environment Variables

Update your `.env` file with:

```env
# Base Network RPC URLs
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

# Keystore account name
DEPLOYER_ACCOUNT=tortoise-deployer

# Etherscan API Key (works for Basescan too)
ETHERSCAN_API_KEY=your_etherscan_api_key_here

# Contract Parameters
PLATFORM_FEE=150000000000000  # 0.00015 ETH in wei
```

## Deployment Process

### Test on Base Sepolia First

1. **Get Test ETH**: Get Base Sepolia ETH from a faucet
2. **Check Balance**: 
   ```bash
   cast balance --account tortoise-deployer --rpc-url base_sepolia
   ```

3. **Deploy to Testnet**:
   ```bash
   forge script script/Deploy.s.sol:DeployToBaseSepolia \
     --account tortoise-deployer \
     --rpc-url base_sepolia \
     --broadcast \
     --verify \
     -vvvv
   ```

### Deploy to Base Mainnet

1. **Ensure Sufficient ETH**: You need ETH on Base mainnet for deployment
2. **Check Balance**:
   ```bash
   cast balance --account tortoise-deployer --rpc-url base
   ```

3. **Dry Run** (simulate without broadcasting):
   ```bash
   forge script script/Deploy.s.sol:DeployToBaseMainnet \
     --account tortoise-deployer \
     --rpc-url base \
     -vvvv
   ```

4. **Deploy to Mainnet**:
   ```bash
   forge script script/Deploy.s.sol:DeployToBaseMainnet \
     --account tortoise-deployer \
     --rpc-url base \
     --broadcast \
     --verify \
     -vvvv
   ```

## Post-Deployment

After deployment, the script will output:
- Contract address
- Transaction hash
- Verification status on Basescan

Save the contract address for future reference!

## Troubleshooting

### "Insufficient funds"
- Make sure your deployer wallet has enough ETH for gas
- Base typically requires ~0.001-0.01 ETH for deployment

### Verification fails
- Wait a few minutes after deployment before verification
- Ensure your Etherscan API key is valid
- Try manual verification: `forge verify-contract <ADDRESS> src/tortoise_v0_3.sol:tortoise_v0_3 --chain base`

### Keystore password issues
- The password prompt may not show characters as you type
- If you forget the password, you'll need to reimport the private key

## Security Reminders

1. **Never commit**:
   - Private keys
   - Keystore files
   - `.env` file with sensitive data

2. **After deployment**:
   - Transfer ownership if needed
   - Remove deployment funds from the deployer wallet
   - Consider deleting the keystore if no longer needed: `cast wallet remove tortoise-deployer`

3. **Best Practices**:
   - Always test on testnet first
   - Use a hardware wallet for high-value deployments
   - Keep deployment wallets separate from operational wallets