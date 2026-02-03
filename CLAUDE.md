# Tortoise Contract v0.3 - Development Guide

This guide provides comprehensive instructions for testing, deploying, and verifying the Tortoise v0.3 smart contract using Foundry.

## Project Overview

The Tortoise contract is an ERC1155-based music NFT marketplace that allows artists to create, price, and sell limited edition songs. The contract includes platform fees, batch minting capabilities, and comprehensive access controls.

## Quick Start

```bash
# Install dependencies (already done)
forge install OpenZeppelin/openzeppelin-contracts

# Build the project
forge build

# Run tests
forge test

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

## Testing Strategy

### 1. Unit Tests

Create comprehensive unit tests in `test/TortoiseV0_3.t.sol`:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TortoiseV0_3Test is Test {
    tortoise_v0_3 public tortoise;
    
    address public owner = makeAddr("owner");
    address public artist1 = makeAddr("artist1");
    address public artist2 = makeAddr("artist2");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    
    uint256 public constant PLATFORM_FEE = 0.001 ether;
    
    event SongCreated(
        uint256 indexed songId,
        string title,
        address indexed artist,
        uint256 price,
        uint256 maxSupply
    );
    
    function setUp() public {
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(PLATFORM_FEE);
        vm.stopPrank();
    }
    
    // Song Creation Tests
    function test_CreateSong_Success() public {
        vm.startPrank(artist1);
        
        string memory title = "My First Song";
        uint256 price = 0.1 ether;
        uint256 maxSupply = 100;
        string memory tokenUri = "ipfs://QmExample";
        
        vm.expectEmit(true, true, true, true);
        emit SongCreated(0, title, artist1, price, maxSupply);
        
        tortoise.createSong(title, price, maxSupply, tokenUri);
        
        (
            string memory songTitle,
            address songArtist,
            uint256 songPrice,
            uint256 songMaxSupply,
            uint256 currentSupply,
            bool exists
        ) = tortoise.getSongDetails(0);
        
        assertEq(songTitle, title);
        assertEq(songArtist, artist1);
        assertEq(songPrice, price);
        assertEq(songMaxSupply, maxSupply);
        assertEq(currentSupply, 0);
        assertTrue(exists);
        
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_TitleEmpty() public {
        vm.startPrank(artist1);
        vm.expectRevert("Title cannot be empty");
        tortoise.createSong("", 0.1 ether, 100, "ipfs://");
        vm.stopPrank();
    }
    
    // Minting Tests
    function test_MintSong_Success() public {
        // Create a song first
        vm.startPrank(artist1);
        tortoise.createSong("Test Song", 0.1 ether, 100, "ipfs://test");
        vm.stopPrank();
        
        // Mint the song
        uint256 quantity = 5;
        uint256 totalCost = (0.1 ether * quantity) + PLATFORM_FEE;
        
        vm.deal(buyer1, totalCost);
        vm.startPrank(buyer1);
        
        tortoise.mintSong{value: totalCost}(0, quantity);
        
        assertEq(tortoise.balanceOf(buyer1, 0), quantity);
        assertEq(address(artist1).balance, 0.1 ether * quantity);
        
        vm.stopPrank();
    }
    
    function test_MintSong_RevertWhen_InsufficientPayment() public {
        vm.startPrank(artist1);
        tortoise.createSong("Test Song", 0.1 ether, 100, "ipfs://test");
        vm.stopPrank();
        
        vm.deal(buyer1, 0.1 ether); // Not enough for platform fee
        vm.startPrank(buyer1);
        
        vm.expectRevert("Insufficient payment");
        tortoise.mintSong{value: 0.1 ether}(0, 1);
        
        vm.stopPrank();
    }
    
    // Access Control Tests
    function test_UpdatePlatformFee_OnlyOwner() public {
        vm.startPrank(owner);
        tortoise.updatePlatformFee(0.002 ether);
        assertEq(tortoise.platformFee(), 0.002 ether);
        vm.stopPrank();
        
        vm.startPrank(artist1);
        vm.expectRevert();
        tortoise.updatePlatformFee(0.003 ether);
        vm.stopPrank();
    }
    
    // Pause Tests
    function test_Pause_StopsMinting() public {
        vm.startPrank(artist1);
        tortoise.createSong("Test Song", 0.1 ether, 100, "ipfs://test");
        vm.stopPrank();
        
        vm.startPrank(owner);
        tortoise.pause();
        vm.stopPrank();
        
        vm.deal(buyer1, 1 ether);
        vm.startPrank(buyer1);
        vm.expectRevert();
        tortoise.mintSong{value: 0.11 ether}(0, 1);
        vm.stopPrank();
    }
}
```

### 2. Fuzz Tests

Add fuzz tests to test edge cases:

```solidity
contract TortoiseV0_3FuzzTest is Test {
    tortoise_v0_3 public tortoise;
    address public owner = makeAddr("owner");
    
    function setUp() public {
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(0.001 ether);
        vm.stopPrank();
    }
    
    function testFuzz_CreateSong_VariousSupplies(
        uint256 maxSupply,
        uint256 price
    ) public {
        vm.assume(maxSupply > 0);
        vm.assume(maxSupply <= type(uint128).max);
        vm.assume(price <= 1000 ether);
        
        vm.startPrank(makeAddr("artist"));
        tortoise.createSong(
            "Fuzz Song",
            price,
            maxSupply,
            "ipfs://fuzz"
        );
        
        (, , uint256 songPrice, uint256 songMaxSupply, , ) = 
            tortoise.getSongDetails(0);
            
        assertEq(songPrice, price);
        assertEq(songMaxSupply, maxSupply);
        vm.stopPrank();
    }
    
    function testFuzz_MintQuantities(uint256 quantity) public {
        vm.assume(quantity > 0);
        vm.assume(quantity <= 100000); // MAX_MINT_QUANTITY
        
        address artist = makeAddr("artist");
        vm.startPrank(artist);
        tortoise.createSong("Test", 0.01 ether, quantity, "ipfs://");
        vm.stopPrank();
        
        address buyer = makeAddr("buyer");
        uint256 totalCost = (0.01 ether * quantity) + 0.001 ether;
        vm.deal(buyer, totalCost);
        
        vm.startPrank(buyer);
        tortoise.mintSong{value: totalCost}(0, quantity);
        
        assertEq(tortoise.balanceOf(buyer, 0), quantity);
        vm.stopPrank();
    }
}
```

### 3. Invariant Tests

Test critical invariants:

```solidity
contract TortoiseV0_3InvariantTest is Test {
    tortoise_v0_3 public tortoise;
    Handler public handler;
    
    function setUp() public {
        address owner = makeAddr("owner");
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(0.001 ether);
        vm.stopPrank();
        
        handler = new Handler(tortoise);
        targetContract(address(handler));
    }
    
    function invariant_CurrentSupplyNeverExceedsMaxSupply() public {
        uint256 songCount = handler.songCount();
        for (uint256 i = 0; i < songCount; i++) {
            (, , , uint256 maxSupply, uint256 currentSupply, bool exists) = 
                tortoise.getSongDetails(i);
            if (exists) {
                assertLe(currentSupply, maxSupply);
            }
        }
    }
    
    function invariant_PlatformFeeNeverExceedsMax() public {
        assertLe(tortoise.platformFee(), tortoise.MAX_PLATFORM_FEE());
    }
}

contract Handler {
    tortoise_v0_3 public tortoise;
    uint256 public songCount;
    
    constructor(tortoise_v0_3 _tortoise) {
        tortoise = _tortoise;
    }
    
    function createSong(
        string memory title,
        uint256 price,
        uint256 maxSupply
    ) public {
        if (bytes(title).length == 0) return;
        if (maxSupply == 0) return;
        
        tortoise.createSong(title, price, maxSupply, "ipfs://test");
        songCount++;
    }
    
    function mintSong(uint256 songId, uint256 quantity) public {
        if (songId >= songCount) return;
        if (quantity == 0 || quantity > 100000) return;
        
        try tortoise.getSongDetails(songId) 
            returns (string memory, address, uint256 price, uint256, uint256, bool exists) {
            if (!exists) return;
            
            uint256 totalCost = (price * quantity) + tortoise.platformFee();
            deal(msg.sender, totalCost);
            
            try tortoise.mintSong{value: totalCost}(songId, quantity) {
                // Success
            } catch {
                // Ignore failures
            }
        } catch {
            return;
        }
    }
}
```

## Deployment

### 1. Environment Setup

Create a `.env` file:

```bash
# RPC URLs
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY

# Private Keys (or use hardware wallet)
DEPLOYER_PRIVATE_KEY=0x...

# Etherscan API Keys
ETHERSCAN_API_KEY=YOUR_KEY

# Contract Parameters
PLATFORM_FEE=1000000000000000  # 0.001 ETH in wei
```

### 2. Deployment Script

Create `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";

contract DeployScript is Script {
    function run() public returns (tortoise_v0_3) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 platformFee = vm.envUint("PLATFORM_FEE");
        
        console.log("Deploying Tortoise v0.3...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Platform Fee:", platformFee);
        
        vm.startBroadcast(deployerPrivateKey);
        
        tortoise_v0_3 tortoise = new tortoise_v0_3(platformFee);
        
        console.log("Tortoise deployed at:", address(tortoise));
        console.log("Owner:", tortoise.owner());
        
        vm.stopBroadcast();
        
        return tortoise;
    }
}
```

### 3. Deployment Commands

```bash
# Test deployment locally
forge script script/Deploy.s.sol

# Deploy to Sepolia testnet
forge script script/Deploy.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv

# Deploy to mainnet (be careful!)
forge script script/Deploy.s.sol \
  --rpc-url mainnet \
  --broadcast \
  --verify \
  --gas-estimate-multiplier 120 \
  -vvvv \
  --interactives 1  # Prompts for confirmation
```

## Verification

### Automatic Verification

If automatic verification fails during deployment:

```bash
forge verify-contract \
  --chain sepolia \
  --num-of-optimizations 200 \
  --compiler-version v0.8.30 \
  --constructor-args $(cast abi-encode "constructor(uint256)" 1000000000000000) \
  CONTRACT_ADDRESS \
  src/tortoise_v0_3.sol:tortoise_v0_3
```

### Manual Verification on Etherscan

1. Go to Etherscan's contract verification page
2. Select "Solidity (Single file)" 
3. Compiler version: 0.8.30
4. Optimization: Yes, 200 runs
5. Flatten the contract: `forge flatten src/tortoise_v0_3.sol`
6. Paste the flattened code
7. Add constructor arguments: The platform fee in hex

## Gas Optimization

### Gas Snapshots

```bash
# Create gas snapshot
forge snapshot

# Compare gas usage after changes
forge snapshot --diff
```

### Gas Reports

```bash
# Run tests with gas reporting
forge test --gas-report

# Specific function gas analysis
forge test --match-test test_MintSong --gas-report
```

## Security Considerations

### 1. Reentrancy Protection
The contract uses OpenZeppelin's `ReentrancyGuard` on all functions that transfer ETH.

### 2. Access Control
- Owner-only functions: `updatePlatformFee`, `pause`, `unpause`, `withdrawPlatformFees`
- Artist/Owner functions: `updateSongPrice`, `updateSongMetadata`, `updateArtistAddress`

### 3. Input Validation
- All inputs are validated for empty values, zero amounts, and overflow conditions
- Maximum mint quantity prevents excessive gas usage
- Platform fee is capped at 1 ETH

### 4. Best Practices
- CEI (Checks-Effects-Interactions) pattern followed
- Events emitted for all state changes
- Pausable functionality for emergency stops

## Common Operations

### Creating a Song (Artist)

```bash
cast send CONTRACT_ADDRESS \
  "createSong(string,uint256,uint256,string)" \
  "My Song Title" \
  "100000000000000000" \
  "1000" \
  "ipfs://QmYourHash" \
  --private-key $ARTIST_PRIVATE_KEY
```

### Minting a Song (Buyer)

```bash
# Calculate total cost (price * quantity + platform fee)
# Example: 0.1 ETH * 5 + 0.001 ETH = 0.501 ETH

cast send CONTRACT_ADDRESS \
  "mintSong(uint256,uint256)" \
  "0" \
  "5" \
  --value 501000000000000000 \
  --private-key $BUYER_PRIVATE_KEY
```

### Checking Song Details

```bash
cast call CONTRACT_ADDRESS \
  "getSongDetails(uint256)" \
  "0"
```

## Troubleshooting

### Common Issues

1. **"Insufficient payment"**: Ensure you include the platform fee in addition to the song price
2. **"Would exceed max supply"**: Check current supply vs max supply before minting
3. **"Song does not exist"**: Verify the song ID is correct

### Debug Commands

```bash
# Get detailed transaction trace
cast run TRANSACTION_HASH

# Decode revert reason
cast 4byte-decode REVERT_DATA

# Check contract state
cast call CONTRACT_ADDRESS "platformFee()"
cast call CONTRACT_ADDRESS "songs(uint256)" 0
```

## Next Steps

1. Set up monitoring for contract events
2. Create a subgraph for efficient querying
3. Implement a frontend interface
4. Set up automated testing in CI/CD
5. Consider implementing upgradability if needed

## Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/5.x/)
- [ERC1155 Standard](https://eips.ethereum.org/EIPS/eip-1155)