// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract tortoise_v0_3Test is Test {
    tortoise_v0_3 public tortoise;
    
    // Test accounts
    address public owner = makeAddr("owner");
    address public artist1 = makeAddr("artist1");
    address public artist2 = makeAddr("artist2");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public nonOwner = makeAddr("nonOwner");
    
    // Constants
    uint256 public constant PLATFORM_FEE = 0.001 ether;
    uint256 public constant SONG_PRICE = 0.1 ether;
    uint256 public constant MAX_SUPPLY = 100;
    string public constant SONG_TITLE = "Test Song";
    string public constant TOKEN_URI = "ipfs://QmTest";
    
    // Events
    event SongCreated(
        uint256 indexed songId,
        string title,
        address indexed artist,
        uint256 price,
        uint256 maxSupply
    );
    
    event SongMinted(
        uint256 indexed songId,
        address indexed buyer,
        address indexed artist,
        uint256 quantity,
        uint256 totalPrice
    );
    
    event PlatformFeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event SongPriceUpdated(uint256 indexed songId, uint256 newPrice);
    event ArtistAddressChanged(uint256 indexed songId, address indexed oldArtist, address indexed newArtist);
    event PlatformFeesWithdrawn(address indexed owner, uint256 amount);
    event ContractPaused(address indexed owner);
    event ContractUnpaused(address indexed owner);
    event SongMetadataUpdated(uint256 indexed songId, string newTitle, string newTokenUri);
    
    function setUp() public {
        vm.startPrank(owner);
        tortoise = new tortoise_v0_3(PLATFORM_FEE);
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SONG CREATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CreateSong_Success() public {
        vm.startPrank(artist1);
        
        vm.expectEmit(true, true, true, true);
        emit SongCreated(0, SONG_TITLE, artist1, SONG_PRICE, MAX_SUPPLY);
        
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        // Verify song details
        (
            string memory title,
            address artist,
            uint256 price,
            uint256 maxSupply,
            uint256 currentSupply,
            bool exists
        ) = tortoise.getSongDetails(0);
        
        assertEq(title, SONG_TITLE);
        assertEq(artist, artist1);
        assertEq(price, SONG_PRICE);
        assertEq(maxSupply, MAX_SUPPLY);
        assertEq(currentSupply, 0);
        assertTrue(exists);
        
        // Verify artist songs mapping
        uint256[] memory artistSongs = tortoise.getArtistSongs(artist1);
        assertEq(artistSongs.length, 1);
        assertEq(artistSongs[0], 0);
        
        // Verify token URI
        assertEq(tortoise.uri(0), TOKEN_URI);
        
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_TitleEmpty() public {
        vm.startPrank(artist1);
        vm.expectRevert("Title cannot be empty");
        tortoise.createSong("", SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_MaxSupplyZero() public {
        vm.startPrank(artist1);
        vm.expectRevert("Max supply must be greater than 0");
        tortoise.createSong(SONG_TITLE, SONG_PRICE, 0, TOKEN_URI, artist1);
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_UriEmpty() public {
        vm.startPrank(artist1);
        vm.expectRevert("URI cannot be empty");
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, "", artist1);
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_ContractPaused() public {
        vm.prank(owner);
        tortoise.pause();
        
        vm.startPrank(artist1);
        vm.expectRevert();
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        vm.stopPrank();
    }
    
    function test_CreateSong_WithArtistParameter_Success() public {
        vm.startPrank(buyer1); // buyer1 creates song for artist1
        
        vm.expectEmit(true, true, true, true);
        emit SongCreated(0, SONG_TITLE, artist1, SONG_PRICE, MAX_SUPPLY);
        
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        // Verify song details
        (
            string memory title,
            address artist,
            uint256 price,
            uint256 maxSupply,
            uint256 currentSupply,
            bool exists
        ) = tortoise.getSongDetails(0);
        
        assertEq(title, SONG_TITLE);
        assertEq(artist, artist1); // Should be artist1, not buyer1
        assertEq(price, SONG_PRICE);
        assertEq(maxSupply, MAX_SUPPLY);
        assertEq(currentSupply, 0);
        assertTrue(exists);
        
        // Verify artist songs mapping points to artist1
        uint256[] memory artistSongs = tortoise.getArtistSongs(artist1);
        assertEq(artistSongs.length, 1);
        assertEq(artistSongs[0], 0);
        
        // Verify buyer1 has no songs
        uint256[] memory buyerSongs = tortoise.getArtistSongs(buyer1);
        assertEq(buyerSongs.length, 0);
        
        vm.stopPrank();
    }
    
    function test_CreateSong_RevertWhen_ArtistAddressZero() public {
        vm.startPrank(buyer1);
        vm.expectRevert("Invalid artist address");
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, address(0));
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                              MINTING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_MintSong_SingleQuantity_Success() public {
        // Setup: Create a song
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        // Calculate payment
        uint256 quantity = 1;
        uint256 totalCost = (SONG_PRICE * quantity) + PLATFORM_FEE;
        
        // Record initial balances
        uint256 artistBalanceBefore = artist1.balance;
        uint256 contractBalanceBefore = address(tortoise).balance;
        
        // Mint
        vm.startPrank(buyer1);
        
        vm.expectEmit(true, true, true, true);
        emit SongMinted(0, buyer1, artist1, quantity, totalCost);
        
        tortoise.mintSong{value: totalCost}(0, quantity, buyer1);
        
        // Verify NFT balance
        assertEq(tortoise.balanceOf(buyer1, 0), quantity);
        
        // Verify payment distribution
        assertEq(artist1.balance, artistBalanceBefore + SONG_PRICE);
        assertEq(address(tortoise).balance, contractBalanceBefore + PLATFORM_FEE);
        
        // Verify supply update
        (, , , , uint256 currentSupply, ) = tortoise.getSongDetails(0);
        assertEq(currentSupply, quantity);
        
        vm.stopPrank();
    }
    
    function test_MintSong_MultipleQuantity_Success() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 quantity = 10;
        uint256 totalCost = (SONG_PRICE * quantity) + PLATFORM_FEE;
        
        vm.prank(buyer1);
        tortoise.mintSong{value: totalCost}(0, quantity, buyer1);
        
        assertEq(tortoise.balanceOf(buyer1, 0), quantity);
        
        (, , , , uint256 currentSupply, ) = tortoise.getSongDetails(0);
        assertEq(currentSupply, quantity);
    }
    
    function test_MintSong_WithRecipient_Success() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 quantity = 5;
        uint256 totalCost = (SONG_PRICE * quantity) + PLATFORM_FEE;
        
        // Buyer1 mints for buyer2
        vm.prank(buyer1);
        tortoise.mintSong{value: totalCost}(0, quantity, buyer2);
        
        assertEq(tortoise.balanceOf(buyer2, 0), quantity);
        assertEq(tortoise.balanceOf(buyer1, 0), 0);
    }
    
    function test_MintSong_RevertWhen_InsufficientPayment() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 quantity = 1;
        uint256 insufficientPayment = SONG_PRICE; // Missing platform fee
        
        vm.startPrank(buyer1);
        vm.expectRevert("Insufficient payment");
        tortoise.mintSong{value: insufficientPayment}(0, quantity, buyer1);
        vm.stopPrank();
    }
    
    function test_MintSong_RevertWhen_ExceedsMaxSupply() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, 10, TOKEN_URI, artist1);
        
        uint256 quantity = 11;
        uint256 totalCost = (SONG_PRICE * quantity) + PLATFORM_FEE;
        
        vm.startPrank(buyer1);
        vm.expectRevert("Would exceed max supply");
        tortoise.mintSong{value: totalCost}(0, quantity, buyer1);
        vm.stopPrank();
    }
    
    function test_MintSong_RevertWhen_SongDoesNotExist() public {
        uint256 totalCost = SONG_PRICE + PLATFORM_FEE;
        
        vm.startPrank(buyer1);
        vm.expectRevert("Song does not exist");
        tortoise.mintSong{value: totalCost}(999, 1, buyer1);
        vm.stopPrank();
    }
    
    function test_MintSong_RevertWhen_ZeroQuantity() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(buyer1);
        vm.expectRevert("Invalid quantity");
        tortoise.mintSong{value: PLATFORM_FEE}(0, 0, buyer1);
        vm.stopPrank();
    }
    
    function test_MintSong_RevertWhen_QuantityExceedsMax() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, 1000000, TOKEN_URI, artist1);
        
        uint256 quantity = tortoise.MAX_MINT_QUANTITY() + 1;
        // Just send enough ETH to ensure the call goes through to the quantity check
        
        vm.startPrank(buyer1);
        vm.expectRevert("Invalid quantity");
        tortoise.mintSong{value: 1 ether}(0, quantity, buyer1);
        vm.stopPrank();
    }
    
    function test_MintSong_RefundExcessPayment() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 quantity = 1;
        uint256 totalCost = (SONG_PRICE * quantity) + PLATFORM_FEE;
        uint256 excessPayment = 1 ether;
        uint256 payment = totalCost + excessPayment;
        
        uint256 buyerBalanceBefore = buyer1.balance;
        
        vm.prank(buyer1);
        tortoise.mintSong{value: payment}(0, quantity, buyer1);
        
        // Check refund
        assertEq(buyer1.balance, buyerBalanceBefore - totalCost);
    }
    
    /*//////////////////////////////////////////////////////////////
                           BATCH MINTING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_MintBatchSongs_Success() public {
        // Create multiple songs
        vm.startPrank(artist1);
        tortoise.createSong("Song 1", 0.1 ether, 100, "ipfs://1", artist1);
        tortoise.createSong("Song 2", 0.2 ether, 100, "ipfs://2", artist1);
        tortoise.createSong("Song 3", 0.3 ether, 100, "ipfs://3", artist1);
        vm.stopPrank();
        
        // Prepare batch mint
        uint256[] memory songIds = new uint256[](3);
        songIds[0] = 0;
        songIds[1] = 1;
        songIds[2] = 2;
        
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 1;
        quantities[1] = 2;
        quantities[2] = 3;
        
        uint256 totalCost = (0.1 ether * 1) + (0.2 ether * 2) + (0.3 ether * 3) + PLATFORM_FEE;
        
        // Mint batch
        vm.prank(buyer1);
        tortoise.mintBatchSongs{value: totalCost}(songIds, quantities, buyer1);
        
        // Verify balances
        assertEq(tortoise.balanceOf(buyer1, 0), 1);
        assertEq(tortoise.balanceOf(buyer1, 1), 2);
        assertEq(tortoise.balanceOf(buyer1, 2), 3);
    }
    
    function test_MintBatchSongs_RevertWhen_ArrayLengthMismatch() public {
        uint256[] memory songIds = new uint256[](2);
        uint256[] memory quantities = new uint256[](3);
        
        vm.startPrank(buyer1);
        vm.expectRevert("Arrays length mismatch");
        tortoise.mintBatchSongs{value: 1 ether}(songIds, quantities, buyer1);
        vm.stopPrank();
    }
    
    function test_MintBatchSongs_RevertWhen_BatchSizeTooLarge() public {
        uint256 batchSize = tortoise.MAX_BATCH_SIZE() + 1;
        uint256[] memory songIds = new uint256[](batchSize);
        uint256[] memory quantities = new uint256[](batchSize);
        
        vm.startPrank(buyer1);
        vm.expectRevert("Batch size too large");
        tortoise.mintBatchSongs{value: 1 ether}(songIds, quantities, buyer1);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UpdatePlatformFee_OnlyOwner() public {
        uint256 newFee = 0.002 ether;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, false, false);
        emit PlatformFeeUpdated(PLATFORM_FEE, newFee);
        
        tortoise.updatePlatformFee(newFee);
        assertEq(tortoise.platformFee(), newFee);
        
        vm.stopPrank();
        
        // Non-owner should fail
        vm.startPrank(nonOwner);
        vm.expectRevert();
        tortoise.updatePlatformFee(0.003 ether);
        vm.stopPrank();
    }
    
    function test_UpdatePlatformFee_RevertWhen_FeeTooHigh() public {
        uint256 tooHighFee = tortoise.MAX_PLATFORM_FEE() + 1;
        
        vm.startPrank(owner);
        vm.expectRevert("Fee too high");
        tortoise.updatePlatformFee(tooHighFee);
        vm.stopPrank();
    }
    
    function test_UpdateSongPrice_ByArtist() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 newPrice = 0.2 ether;
        
        vm.startPrank(artist1);
        
        vm.expectEmit(true, false, false, true);
        emit SongPriceUpdated(0, newPrice);
        
        tortoise.updateSongPrice(0, newPrice);
        
        (, , uint256 price, , , ) = tortoise.getSongDetails(0);
        assertEq(price, newPrice);
        
        vm.stopPrank();
    }
    
    function test_UpdateSongPrice_ByOwner() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        uint256 newPrice = 0.2 ether;
        
        vm.prank(owner);
        tortoise.updateSongPrice(0, newPrice);
        
        (, , uint256 price, , , ) = tortoise.getSongDetails(0);
        assertEq(price, newPrice);
    }
    
    function test_UpdateSongPrice_RevertWhen_NotAuthorized() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(artist2);
        vm.expectRevert("Not artist or owner");
        tortoise.updateSongPrice(0, 0.2 ether);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          PAUSE/UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Pause_Success() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit ContractPaused(owner);
        
        tortoise.pause();
        
        vm.stopPrank();
        
        // Verify paused functions revert
        vm.startPrank(artist1);
        vm.expectRevert();
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        vm.stopPrank();
    }
    
    function test_Unpause_Success() public {
        vm.prank(owner);
        tortoise.pause();
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit ContractUnpaused(owner);
        
        tortoise.unpause();
        
        vm.stopPrank();
        
        // Verify unpaused functions work
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
    }
    
    function test_Pause_RevertWhen_NotOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        tortoise.pause();
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        METADATA UPDATE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UpdateSongMetadata_Success() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        string memory newTitle = "Updated Title";
        string memory newTokenUri = "ipfs://QmUpdated";
        
        vm.startPrank(artist1);
        
        vm.expectEmit(true, false, false, true);
        emit SongMetadataUpdated(0, newTitle, newTokenUri);
        
        tortoise.updateSongMetadata(0, newTitle, newTokenUri);
        
        (string memory title, , , , , ) = tortoise.getSongDetails(0);
        assertEq(title, newTitle);
        assertEq(tortoise.uri(0), newTokenUri);
        
        vm.stopPrank();
    }
    
    function test_UpdateSongMetadata_RevertWhen_TitleEmpty() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(artist1);
        vm.expectRevert("Title cannot be empty");
        tortoise.updateSongMetadata(0, "", "ipfs://new");
        vm.stopPrank();
    }
    
    function test_UpdateSongMetadata_RevertWhen_UriEmpty() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(artist1);
        vm.expectRevert("URI cannot be empty");
        tortoise.updateSongMetadata(0, "New Title", "");
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ARTIST ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UpdateArtistAddress_Success() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(artist1);
        
        vm.expectEmit(true, true, true, false);
        emit ArtistAddressChanged(0, artist1, artist2);
        
        tortoise.updateArtistAddress(0, artist2);
        
        (, address artist, , , , ) = tortoise.getSongDetails(0);
        assertEq(artist, artist2);
        
        // Check artist songs mappings updated
        uint256[] memory artist1Songs = tortoise.getArtistSongs(artist1);
        uint256[] memory artist2Songs = tortoise.getArtistSongs(artist2);
        
        assertEq(artist1Songs.length, 0);
        assertEq(artist2Songs.length, 1);
        assertEq(artist2Songs[0], 0);
        
        vm.stopPrank();
    }
    
    function test_UpdateArtistAddress_RevertWhen_AddressZero() public {
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.startPrank(artist1);
        vm.expectRevert("Invalid new artist address");
        tortoise.updateArtistAddress(0, address(0));
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                      WITHDRAWAL AND RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_WithdrawPlatformFees_Success() public {
        // Create and mint songs to accumulate fees
        vm.prank(artist1);
        tortoise.createSong(SONG_TITLE, SONG_PRICE, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.prank(buyer1);
        tortoise.mintSong{value: SONG_PRICE + PLATFORM_FEE}(0, 1, buyer1);
        
        uint256 contractBalance = address(tortoise).balance;
        uint256 ownerBalanceBefore = owner.balance;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit PlatformFeesWithdrawn(owner, contractBalance);
        
        tortoise.withdrawPlatformFees();
        
        assertEq(address(tortoise).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + contractBalance);
        
        vm.stopPrank();
    }
    
    function test_WithdrawPlatformFees_RevertWhen_NoFees() public {
        vm.startPrank(owner);
        vm.expectRevert("No fees to withdraw");
        tortoise.withdrawPlatformFees();
        vm.stopPrank();
    }
    
    function test_WithdrawPlatformFees_RevertWhen_NotOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        tortoise.withdrawPlatformFees();
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_MintSong_FreeSong() public {
        vm.prank(artist1);
        tortoise.createSong("Free Song", 0, MAX_SUPPLY, TOKEN_URI, artist1);
        
        vm.prank(buyer1);
        tortoise.mintSong{value: PLATFORM_FEE}(0, 1, buyer1);
        
        assertEq(tortoise.balanceOf(buyer1, 0), 1);
    }
    
    function test_CreateMultipleSongs_DifferentArtists() public {
        vm.prank(artist1);
        tortoise.createSong("Artist1 Song", SONG_PRICE, MAX_SUPPLY, "ipfs://1", artist1);
        
        vm.prank(artist2);
        tortoise.createSong("Artist2 Song", SONG_PRICE * 2, MAX_SUPPLY * 2, "ipfs://2", artist2);
        
        // Verify song IDs
        (string memory title1, address artist1Addr, , , , ) = tortoise.getSongDetails(0);
        (string memory title2, address artist2Addr, , , , ) = tortoise.getSongDetails(1);
        
        assertEq(title1, "Artist1 Song");
        assertEq(artist1Addr, artist1);
        assertEq(title2, "Artist2 Song");
        assertEq(artist2Addr, artist2);
    }
    
    function test_Uri_RevertWhen_NonExistentToken() public {
        vm.expectRevert("URI query for nonexistent token");
        tortoise.uri(999);
    }
    
    function test_GetSongDetails_RevertWhen_NonExistentSong() public {
        vm.expectRevert("Song does not exist");
        tortoise.getSongDetails(999);
    }
}