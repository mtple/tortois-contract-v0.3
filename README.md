# Tortoise v0.3

An ERC1155-based music NFT marketplace smart contract that allows artists to create, price, and sell limited edition songs.

## Features

- **Song Creation**: Artists can create songs with custom pricing, max supply, and metadata
- **Minting**: Buyers can mint single songs or batch mint multiple songs
- **Artist Payments**: Automatic payment distribution to artists on mint
- **Platform Fees**: Configurable platform fee (capped at 1 ETH)
- **Access Control**: Owner and artist-level permissions for updates
- **Pausable**: Emergency pause functionality
- **Token Recovery**: Recover accidentally sent ERC20 tokens

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

```bash
# Clone the repo
git clone https://github.com/mtple/tortois-contract-v0.3.git
cd tortois-contract-v0.3

# Install dependencies
forge install

# Build
forge build
```

### Testing

```bash
forge test
```

### Deployment

1. Copy `.env.example` to `.env` and fill in your values
2. Deploy:

```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --verify
```

## Contract Overview

| Function | Description |
|----------|-------------|
| `createSong` | Create a new song with title, price, max supply, and metadata URI |
| `mintSong` | Mint copies of a song (pays artist + platform fee) |
| `mintBatchSongs` | Mint multiple songs in one transaction |
| `updateSongPrice` | Update song price (artist or owner only) |
| `updateSongMetadata` | Update song title and URI (artist or owner only) |
| `updateArtistAddress` | Transfer song ownership to new artist |
| `getSongDetails` | Get song information |
| `getArtistSongs` | Get all song IDs for an artist |

## Security

- Reentrancy protection on all payment functions
- Pausable for emergency stops
- Platform fee capped at 1 ETH
- Input validation on all public functions

## License

Apache-2.0
