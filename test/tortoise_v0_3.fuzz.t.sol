// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";

contract tortoise_v0_3FuzzTest is Test {
    tortoise_v0_3 public tortoise;
    address public owner = makeAddr("owner");
    address public artist = makeAddr("artist");
    
    function setUp() public {
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(0.001 ether);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          SONG CREATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_CreateSong_WithArtistParameter(
        string memory title,
        uint256 price,
        uint256 maxSupply,
        string memory tokenUri,
        address targetArtist
    ) public {
        // Bound inputs to valid ranges
        vm.assume(bytes(title).length > 0 && bytes(title).length < 1000);
        vm.assume(maxSupply > 0 && maxSupply <= type(uint128).max);
        vm.assume(bytes(tokenUri).length > 0 && bytes(tokenUri).length < 1000);
        vm.assume(price <= 1000 ether);
        vm.assume(targetArtist != address(0));
        
        vm.startPrank(owner); // owner creates song for targetArtist
        tortoise.createSong(title, price, maxSupply, tokenUri, targetArtist);
        
        (
            string memory songTitle,
            address songArtist,
            uint256 songPrice,
            uint256 songMaxSupply,
            uint256 currentSupply,
            bool exists
        ) = tortoise.getSongDetails(0);
        
        assertEq(songTitle, title);
        assertEq(songArtist, targetArtist); // Should be targetArtist, not owner
        assertEq(songPrice, price);
        assertEq(songMaxSupply, maxSupply);
        assertEq(currentSupply, 0);
        assertTrue(exists);
        assertEq(tortoise.uri(0), tokenUri);
        
        // Verify artist songs mapping
        uint256[] memory artistSongs = tortoise.getArtistSongs(targetArtist);
        assertEq(artistSongs.length, 1);
        assertEq(artistSongs[0], 0);
        
        vm.stopPrank();
    }

    function testFuzz_CreateSong_VariousParameters(
        string memory title,
        uint256 price,
        uint256 maxSupply,
        string memory tokenUri
    ) public {
        // Bound inputs to valid ranges
        vm.assume(bytes(title).length > 0 && bytes(title).length < 1000);
        vm.assume(maxSupply > 0 && maxSupply <= type(uint128).max);
        vm.assume(bytes(tokenUri).length > 0 && bytes(tokenUri).length < 1000);
        vm.assume(price <= 1000 ether); // Reasonable price limit
        
        vm.startPrank(artist);
        tortoise.createSong(title, price, maxSupply, tokenUri, artist);
        
        (
            string memory songTitle,
            address songArtist,
            uint256 songPrice,
            uint256 songMaxSupply,
            uint256 currentSupply,
            bool exists
        ) = tortoise.getSongDetails(0);
        
        assertEq(songTitle, title);
        assertEq(songArtist, artist);
        assertEq(songPrice, price);
        assertEq(songMaxSupply, maxSupply);
        assertEq(currentSupply, 0);
        assertTrue(exists);
        assertEq(tortoise.uri(0), tokenUri);
        
        vm.stopPrank();
    }
    
    function testFuzz_CreateMultipleSongs(uint8 numberOfSongs) public {
        vm.assume(numberOfSongs > 0 && numberOfSongs <= 50); // Reasonable limit
        
        vm.startPrank(artist);
        
        for (uint256 i = 0; i < numberOfSongs; i++) {
            string memory title = string(abi.encodePacked("Song ", vm.toString(i)));
            tortoise.createSong(title, 0.1 ether * i, 100 + i, string(abi.encodePacked("ipfs://", vm.toString(i))), artist);
        }
        
        vm.stopPrank();
        
        // Verify artist songs
        uint256[] memory artistSongs = tortoise.getArtistSongs(artist);
        assertEq(artistSongs.length, numberOfSongs);
        
        // Verify each song
        for (uint256 i = 0; i < numberOfSongs; i++) {
            assertEq(artistSongs[i], i);
            (, address songArtist, , , , bool exists) = tortoise.getSongDetails(i);
            assertTrue(exists);
            assertEq(songArtist, artist);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                            MINTING FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_MintSong_VariousQuantities(
        uint256 quantity,
        uint256 songPrice,
        uint256 maxSupply
    ) public {
        // Bound inputs
        quantity = bound(quantity, 1, tortoise.MAX_MINT_QUANTITY());
        maxSupply = bound(maxSupply, quantity, type(uint128).max);
        songPrice = bound(songPrice, 0, 100 ether);
        
        // Create song
        vm.prank(artist);
        tortoise.createSong("Fuzz Song", songPrice, maxSupply, "ipfs://fuzz", artist);
        
        // Calculate payment
        uint256 totalCost = (songPrice * quantity) + tortoise.platformFee();
        
        // Mint
        address buyer = makeAddr("buyer");
        vm.deal(buyer, totalCost);
        
        uint256 artistBalanceBefore = artist.balance;
        
        vm.prank(buyer);
        tortoise.mintSong{value: totalCost}(0, quantity, buyer);
        
        // Verify
        assertEq(tortoise.balanceOf(buyer, 0), quantity);
        assertEq(artist.balance, artistBalanceBefore + (songPrice * quantity));
        
        (, , , , uint256 currentSupply, ) = tortoise.getSongDetails(0);
        assertEq(currentSupply, quantity);
    }
    
    function testFuzz_MintSong_WithExcessPayment(
        uint256 quantity,
        uint256 excessAmount
    ) public {
        quantity = bound(quantity, 1, 100);
        excessAmount = bound(excessAmount, 1 wei, 10 ether);
        
        uint256 songPrice = 0.1 ether;
        
        vm.prank(artist);
        tortoise.createSong("Test Song", songPrice, 1000, "ipfs://test", artist);
        
        uint256 totalCost = (songPrice * quantity) + tortoise.platformFee();
        uint256 payment = totalCost + excessAmount;
        
        address buyer = makeAddr("buyer");
        vm.deal(buyer, payment);
        
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.prank(buyer);
        tortoise.mintSong{value: payment}(0, quantity, buyer);
        
        // Verify refund
        assertEq(buyer.balance, buyerBalanceBefore - totalCost);
    }
    
    function testFuzz_MintBatchSongs(
        uint8 numberOfSongs,
        uint8 seed
    ) public {
        numberOfSongs = uint8(bound(numberOfSongs, 1, 10));
        
        // Create songs
        vm.startPrank(artist);
        for (uint256 i = 0; i < numberOfSongs; i++) {
            tortoise.createSong(
                string(abi.encodePacked("Song ", vm.toString(i))),
                0.01 ether * (i + 1),
                100,
                string(abi.encodePacked("ipfs://", vm.toString(i))),
                artist
            );
        }
        vm.stopPrank();
        
        // Prepare batch mint arrays
        uint256[] memory songIds = new uint256[](numberOfSongs);
        uint256[] memory quantities = new uint256[](numberOfSongs);
        uint256 totalCost = tortoise.platformFee();
        
        for (uint256 i = 0; i < numberOfSongs; i++) {
            songIds[i] = i;
            quantities[i] = (uint256(keccak256(abi.encode(seed, i))) % 10) + 1; // 1-10 quantity
            (, , uint256 price, , , ) = tortoise.getSongDetails(i);
            totalCost += price * quantities[i];
        }
        
        // Mint batch
        address buyer = makeAddr("buyer");
        vm.deal(buyer, totalCost);
        
        vm.prank(buyer);
        tortoise.mintBatchSongs{value: totalCost}(songIds, quantities, buyer);
        
        // Verify all balances
        for (uint256 i = 0; i < numberOfSongs; i++) {
            assertEq(tortoise.balanceOf(buyer, i), quantities[i]);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                          PLATFORM FEE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_UpdatePlatformFee(uint256 newFee) public {
        newFee = bound(newFee, 0, tortoise.MAX_PLATFORM_FEE());
        
        vm.prank(owner);
        tortoise.updatePlatformFee(newFee);
        
        assertEq(tortoise.platformFee(), newFee);
    }
    
    function testFuzz_PlatformFeeCollection(
        uint8 numberOfMints,
        uint256 platformFee
    ) public {
        numberOfMints = uint8(bound(numberOfMints, 1, 50));
        platformFee = bound(platformFee, 1, tortoise.MAX_PLATFORM_FEE());
        
        // Set platform fee
        vm.prank(owner);
        tortoise.updatePlatformFee(platformFee);
        
        // Create a song
        vm.prank(artist);
        tortoise.createSong("Test Song", 0.1 ether, 1000, "ipfs://test", artist);
        
        uint256 expectedFees = 0;
        
        // Multiple buyers mint
        for (uint256 i = 0; i < numberOfMints; i++) {
            address buyer = makeAddr(string(abi.encodePacked("buyer", i)));
            uint256 totalCost = 0.1 ether + platformFee;
            vm.deal(buyer, totalCost);
            
            vm.prank(buyer);
            tortoise.mintSong{value: totalCost}(0, 1, buyer);
            
            expectedFees += platformFee;
        }
        
        assertEq(address(tortoise).balance, expectedFees);
        
        // Withdraw fees if there are any
        if (expectedFees > 0) {
            uint256 ownerBalanceBefore = owner.balance;
            
            vm.prank(owner);
            tortoise.withdrawPlatformFees();
            
            assertEq(owner.balance, ownerBalanceBefore + expectedFees);
            assertEq(address(tortoise).balance, 0);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        METADATA UPDATE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_UpdateSongMetadata(
        string memory originalTitle,
        string memory newTitle,
        string memory originalUri,
        string memory newUri
    ) public {
        // Bound inputs
        vm.assume(bytes(originalTitle).length > 0 && bytes(originalTitle).length < 100);
        vm.assume(bytes(newTitle).length > 0 && bytes(newTitle).length < 100);
        vm.assume(bytes(originalUri).length > 0 && bytes(originalUri).length < 200);
        vm.assume(bytes(newUri).length > 0 && bytes(newUri).length < 200);
        
        // Create song
        vm.prank(artist);
        tortoise.createSong(originalTitle, 0.1 ether, 100, originalUri, artist);
        
        // Update metadata
        vm.prank(artist);
        tortoise.updateSongMetadata(0, newTitle, newUri);
        
        // Verify
        (string memory title, , , , , ) = tortoise.getSongDetails(0);
        assertEq(title, newTitle);
        assertEq(tortoise.uri(0), newUri);
    }
    
    /*//////////////////////////////////////////////////////////////
                      ARTIST ADDRESS UPDATE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_UpdateArtistAddress(address newArtist) public {
        vm.assume(newArtist != address(0));
        vm.assume(newArtist != artist);
        
        // Create multiple songs
        vm.startPrank(artist);
        tortoise.createSong("Song 1", 0.1 ether, 100, "ipfs://1", artist);
        tortoise.createSong("Song 2", 0.2 ether, 200, "ipfs://2", artist);
        tortoise.createSong("Song 3", 0.3 ether, 300, "ipfs://3", artist);
        vm.stopPrank();
        
        // Update artist for song 1
        vm.prank(artist);
        tortoise.updateArtistAddress(1, newArtist);
        
        // Verify
        (, address artist1, , , , ) = tortoise.getSongDetails(1);
        assertEq(artist1, newArtist);
        
        // Check mappings
        uint256[] memory originalArtistSongs = tortoise.getArtistSongs(artist);
        uint256[] memory newArtistSongs = tortoise.getArtistSongs(newArtist);
        
        assertEq(originalArtistSongs.length, 2); // Should have songs 0 and 2
        assertEq(newArtistSongs.length, 1); // Should have song 1
        assertEq(newArtistSongs[0], 1);
    }
    
    /*//////////////////////////////////////////////////////////////
                          PRICE UPDATE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_UpdateSongPrice(
        uint256 originalPrice,
        uint256 newPrice,
        bool updateByOwner
    ) public {
        originalPrice = bound(originalPrice, 0, 100 ether);
        newPrice = bound(newPrice, 0, 100 ether);
        
        // Create song
        vm.prank(artist);
        tortoise.createSong("Test Song", originalPrice, 100, "ipfs://test", artist);
        
        // Update price
        address updater = updateByOwner ? owner : artist;
        vm.prank(updater);
        tortoise.updateSongPrice(0, newPrice);
        
        // Verify
        (, , uint256 price, , , ) = tortoise.getSongDetails(0);
        assertEq(price, newPrice);
        
        // Test minting with new price
        address buyer = makeAddr("buyer");
        uint256 totalCost = newPrice + tortoise.platformFee();
        vm.deal(buyer, totalCost);
        
        vm.prank(buyer);
        tortoise.mintSong{value: totalCost}(0, 1, buyer);
        
        assertEq(tortoise.balanceOf(buyer, 0), 1);
    }
}