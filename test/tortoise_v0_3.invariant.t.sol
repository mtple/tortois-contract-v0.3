// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";

contract Handler is Test {
    tortoise_v0_3 public immutable tortoise;
    
    // Ghost variables to track state
    uint256 public ghost_totalPlatformFeesCollected;
    uint256 public ghost_totalArtistPayments;
    mapping(uint256 => uint256) public ghost_songMintCounts;
    uint256 public songCount;
    
    // Track actors
    address[] public artists;
    address[] public buyers;
    
    modifier useActor(address[] storage actors, uint256 seed) {
        if (actors.length == 0) return;
        address actor = actors[seed % actors.length];
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }
    
    constructor(tortoise_v0_3 _tortoise) {
        tortoise = _tortoise;
        
        // Initialize actors
        for (uint256 i = 0; i < 5; i++) {
            artists.push(makeAddr(string(abi.encodePacked("artist", i))));
            buyers.push(makeAddr(string(abi.encodePacked("buyer", i))));
            
            // Fund buyers
            deal(buyers[i], 1000 ether);
        }
    }
    
    function createSong(
        uint256 artistSeed,
        string calldata title,
        uint256 price,
        uint256 maxSupply
    ) external useActor(artists, artistSeed) {
        // Bound inputs
        if (bytes(title).length == 0) return;
        if (maxSupply == 0) return;
        if (price > 100 ether) return;
        
        address artist = artists[artistSeed % artists.length];
        string memory uri = string(abi.encodePacked("ipfs://", vm.toString(songCount)));
        
        try tortoise.createSong(title, price, maxSupply, uri, artist) {
            songCount++;
        } catch {
            // Ignore failures (e.g., paused contract)
        }
    }
    
    function mintSong(
        uint256 buyerSeed,
        uint256 songId,
        uint256 quantity
    ) external useActor(buyers, buyerSeed) {
        // Validate inputs
        if (songId >= songCount) return;
        if (quantity == 0 || quantity > tortoise.MAX_MINT_QUANTITY()) return;
        
        // Get song details
        (bool exists, uint256 price, uint256 maxSupply, uint256 currentSupply) = _getSongInfo(songId);
        
        if (!exists) return;
        if (currentSupply + quantity > maxSupply) return;
        
        uint256 totalCost = (price * quantity) + tortoise.platformFee();
        
        address buyer = buyers[buyerSeed % buyers.length];
        try tortoise.mintSong{value: totalCost}(songId, quantity, buyer) {
            // Update ghost variables
            ghost_totalPlatformFeesCollected += tortoise.platformFee();
            ghost_totalArtistPayments += (price * quantity);
            ghost_songMintCounts[songId] += quantity;
        } catch {
            // Ignore failures
        }
    }
    
    function _getSongInfo(uint256 songId) internal view returns (
        bool exists,
        uint256 price,
        uint256 maxSupply,
        uint256 currentSupply
    ) {
        try tortoise.getSongDetails(songId) returns (
            string memory,
            address,
            uint256 _price,
            uint256 _maxSupply,
            uint256 _currentSupply,
            bool _exists
        ) {
            return (_exists, _price, _maxSupply, _currentSupply);
        } catch {
            return (false, 0, 0, 0);
        }
    }
    
    function mintBatchSongs(
        uint256 buyerSeed,
        uint256 batchSizeSeed
    ) external useActor(buyers, buyerSeed) {
        uint256 batchSize = (batchSizeSeed % 5) + 1; // 1-5 songs
        if (batchSize > songCount) return;
        
        uint256[] memory songIds = new uint256[](batchSize);
        uint256[] memory quantities = new uint256[](batchSize);
        uint256 totalCost = tortoise.platformFee();
        
        // Prepare batch
        for (uint256 i = 0; i < batchSize; i++) {
            songIds[i] = i % songCount;
            quantities[i] = (i % 3) + 1; // 1-3 quantity
            
            try tortoise.getSongDetails(songIds[i]) returns (
                string memory,
                address,
                uint256 price,
                uint256 maxSupply,
                uint256 currentSupply,
                bool exists
            ) {
                if (!exists) return;
                if (currentSupply + quantities[i] > maxSupply) return;
                totalCost += price * quantities[i];
            } catch {
                return;
            }
        }
        
        address buyer = buyers[buyerSeed % buyers.length];
        try tortoise.mintBatchSongs{value: totalCost}(songIds, quantities, buyer) {
            ghost_totalPlatformFeesCollected += tortoise.platformFee();
            for (uint256 i = 0; i < batchSize; i++) {
                ghost_songMintCounts[songIds[i]] += quantities[i];
            }
        } catch {
            // Ignore failures
        }
    }
    
    function updateSongPrice(
        uint256 actorSeed,
        uint256 songId,
        uint256 newPrice
    ) external {
        if (songId >= songCount) return;
        if (newPrice > 100 ether) return;
        
        try tortoise.getSongDetails(songId) returns (
            string memory,
            address artist,
            uint256,
            uint256,
            uint256,
            bool exists
        ) {
            if (!exists) return;
            
            // Either artist or owner can update
            address actor = actorSeed % 2 == 0 ? artist : tortoise.owner();
            
            vm.prank(actor);
            try tortoise.updateSongPrice(songId, newPrice) {
                // Success
            } catch {
                // Ignore failures
            }
        } catch {
            return;
        }
    }
    
    function withdrawFees() external {
        if (address(tortoise).balance == 0) return;
        
        uint256 balanceBefore = address(tortoise).balance;
        
        vm.prank(tortoise.owner());
        try tortoise.withdrawPlatformFees() {
            // Verify all fees were withdrawn
            assert(address(tortoise).balance == 0);
            assert(tortoise.owner().balance >= balanceBefore);
        } catch {
            // Ignore failures
        }
    }
}

contract tortoise_v0_3InvariantTest is Test {
    tortoise_v0_3 public tortoise;
    Handler public handler;
    
    function setUp() public {
        address owner = makeAddr("owner");
        
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(0.001 ether);
        vm.stopPrank();
        
        handler = new Handler(tortoise);
        
        // Target only the handler
        targetContract(address(handler));
    }
    
    /*//////////////////////////////////////////////////////////////
                          SUPPLY INVARIANTS
    //////////////////////////////////////////////////////////////*/
    
    function invariant_CurrentSupplyNeverExceedsMaxSupply() public {
        for (uint256 i = 0; i < handler.songCount(); i++) {
            try tortoise.getSongDetails(i) returns (
                string memory,
                address,
                uint256,
                uint256 maxSupply,
                uint256 currentSupply,
                bool exists
            ) {
                if (exists) {
                    assertLe(
                        currentSupply,
                        maxSupply,
                        "Current supply exceeds max supply"
                    );
                }
            } catch {
                // Song doesn't exist
            }
        }
    }
    
    function invariant_MintedQuantityMatchesBalances() public {
        for (uint256 songId = 0; songId < handler.songCount(); songId++) {
            uint256 totalMinted = 0;
            
            // Sum up all buyer balances for this song
            for (uint256 j = 0; j < 5; j++) {
                address buyer = handler.buyers(j);
                totalMinted += tortoise.balanceOf(buyer, songId);
            }
            
            // Check against current supply
            try tortoise.getSongDetails(songId) returns (
                string memory,
                address,
                uint256,
                uint256,
                uint256 currentSupply,
                bool exists
            ) {
                if (exists) {
                    assertGe(
                        currentSupply,
                        totalMinted,
                        "Current supply less than minted tokens"
                    );
                }
            } catch {
                // Song doesn't exist
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                          FINANCIAL INVARIANTS
    //////////////////////////////////////////////////////////////*/
    
    function invariant_PlatformFeeNeverExceedsMax() public {
        assertLe(
            tortoise.platformFee(),
            tortoise.MAX_PLATFORM_FEE(),
            "Platform fee exceeds maximum"
        );
    }
    
    function invariant_ContractBalanceMatchesPlatformFees() public {
        // Contract balance should equal collected platform fees minus withdrawn fees
        // Note: This is a simplified check as we can't track withdrawals perfectly
        assertGe(
            handler.ghost_totalPlatformFeesCollected(),
            address(tortoise).balance,
            "Contract balance exceeds collected fees"
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                         OWNERSHIP INVARIANTS
    //////////////////////////////////////////////////////////////*/
    
    function invariant_SongArtistNeverZeroAddress() public {
        for (uint256 i = 0; i < handler.songCount(); i++) {
            try tortoise.getSongDetails(i) returns (
                string memory,
                address artist,
                uint256,
                uint256,
                uint256,
                bool exists
            ) {
                if (exists) {
                    assertTrue(
                        artist != address(0),
                        "Song artist is zero address"
                    );
                }
            } catch {
                // Song doesn't exist
            }
        }
    }
    
    function invariant_ArtistSongsMappingConsistency() public {
        // For each artist, verify their songs list is accurate
        for (uint256 i = 0; i < 5; i++) {
            address artist = handler.artists(i);
            uint256[] memory artistSongs = tortoise.getArtistSongs(artist);
            
            for (uint256 j = 0; j < artistSongs.length; j++) {
                uint256 songId = artistSongs[j];
                
                try tortoise.getSongDetails(songId) returns (
                    string memory,
                    address songArtist,
                    uint256,
                    uint256,
                    uint256,
                    bool exists
                ) {
                    assertTrue(exists, "Non-existent song in artist mapping");
                    assertEq(
                        songArtist,
                        artist,
                        "Artist mapping mismatch"
                    );
                } catch {
                    fail("Song in artist mapping doesn't exist");
                }
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE INVARIANTS
    //////////////////////////////////////////////////////////////*/
    
    function invariant_SongIdMonotonicallyIncreases() public {
        // Verify no gaps in song IDs
        bool foundNonExistent = false;
        
        for (uint256 i = 0; i < handler.songCount() + 10; i++) {
            try tortoise.getSongDetails(i) returns (
                string memory,
                address,
                uint256,
                uint256,
                uint256,
                bool exists
            ) {
                if (!exists && i < handler.songCount()) {
                    fail("Gap in song IDs");
                }
                if (exists && foundNonExistent) {
                    fail("Song exists after non-existent song");
                }
            } catch {
                foundNonExistent = true;
            }
        }
    }
    
    function invariant_CallSummary() public view {
        console.log("=== Invariant Test Summary ===");
        console.log("Songs created:", handler.songCount());
        console.log("Total platform fees collected:", handler.ghost_totalPlatformFeesCollected());
        console.log("Total artist payments:", handler.ghost_totalArtistPayments());
        console.log("Contract balance:", address(tortoise).balance);
    }
}