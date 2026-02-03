// SPDX-License-Identifier: Apache-2.0
//         _____     ____
//        /      \  |  o |
//       |        |/ ___\|
//       |_________/
//       |_|_| |_|_|
//
// tortoise.studio
//
pragma solidity 0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract tortoise_v0_3 is ERC1155, Ownable, ReentrancyGuard, Pausable {
    uint256 public constant MAX_MINT_QUANTITY = 100000;
    uint256 public constant MAX_PLATFORM_FEE = 1 ether;
    uint256 public constant MAX_BATCH_SIZE = 50;

    uint256 private _nextSongId;
    uint256 public platformFee;

    string private _name = "Tortoise";
    string private _symbol = "TORT";

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    struct Song {
        string title;
        address artist;
        uint256 price;
        uint256 maxSupply;
        uint256 currentSupply;
        bool exists;
    }

    mapping(uint256 => Song) public songs;
    mapping(address => uint256[]) public artistSongs;
    mapping(uint256 => string) private tokenUris;

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
    event ArtistAddressChanged(
        uint256 indexed songId,
        address indexed oldArtist,
        address indexed newArtist
    );

    event PlatformFeesWithdrawn(address indexed owner, uint256 amount);
    event ContractPaused(address indexed owner);
    event ContractUnpaused(address indexed owner);
    event SongMetadataUpdated(
        uint256 indexed songId,
        string newTitle,
        string newTokenUri
    );
    event TokensRecovered(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    constructor(uint256 _platformFee) ERC1155("") Ownable(msg.sender) {
        require(_platformFee <= MAX_PLATFORM_FEE, "Platform fee too high");
        platformFee = _platformFee;
    }

    function createSong(
        string memory title,
        uint256 price,
        uint256 maxSupply,
        string memory tokenUri,
        address artist
    ) public whenNotPaused {
        require(bytes(title).length > 0, "Title cannot be empty");
        require(maxSupply > 0, "Max supply must be greater than 0");
        require(bytes(tokenUri).length > 0, "URI cannot be empty");
        require(artist != address(0), "Invalid artist address");

        uint256 newSongId = _nextSongId;
        _nextSongId += 1;

        songs[newSongId] = Song({
            title: title,
            artist: artist,
            price: price,
            maxSupply: maxSupply,
            currentSupply: 0,
            exists: true
        });

        artistSongs[artist].push(newSongId);

        tokenUris[newSongId] = tokenUri;

        emit SongCreated(newSongId, title, artist, price, maxSupply);
    }


    function mintSong(
        uint256 songId,
        uint256 quantity,
        address recipient
    ) public payable nonReentrant whenNotPaused {
        require(
            quantity > 0 && quantity <= MAX_MINT_QUANTITY,
            "Invalid quantity"
        );
        require(recipient != address(0), "Invalid recipient address");

        Song storage song = songs[songId];
        require(song.exists, "Song does not exist");
        require(
            song.currentSupply + quantity <= song.maxSupply,
            "Would exceed max supply"
        );

        uint256 totalCost = (song.price * quantity) + platformFee;
        require(msg.value >= totalCost, "Insufficient payment");

        _mint(recipient, songId, quantity, "");
        song.currentSupply += quantity;

        uint256 artistPayment = song.price * quantity;
        address artistAddress = song.artist;

        (bool success, ) = payable(artistAddress).call{value: artistPayment}("");
        require(success, "Artist payment failed");
        
        if (msg.value > totalCost) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(refundSuccess, "Refund failed");
        }

        emit SongMinted(songId, recipient, song.artist, quantity, totalCost);
    }


    function mintBatchSongs(
        uint256[] memory songIds,
        uint256[] memory quantities,
        address recipient
    ) public payable nonReentrant whenNotPaused {
        require(songIds.length == quantities.length, "Arrays length mismatch");
        require(songIds.length <= MAX_BATCH_SIZE, "Batch size too large");
        require(recipient != address(0), "Invalid recipient address");

        uint256 totalCost = platformFee;
        uint256[] memory costs = new uint256[](songIds.length);
        address[] memory artistAddresses = new address[](songIds.length);

        for (uint256 i = 0; i < songIds.length; i++) {
            require(
                quantities[i] > 0 && quantities[i] <= MAX_MINT_QUANTITY,
                "Invalid quantity"
            );
            Song storage song = songs[songIds[i]];
            require(song.exists, "Song does not exist");
            require(
                song.currentSupply + quantities[i] <= song.maxSupply,
                "Would exceed max supply"
            );
            costs[i] = song.price * quantities[i];
            artistAddresses[i] = song.artist;
            totalCost += costs[i];
        }

        require(msg.value >= totalCost, "Insufficient payment");

        for (uint256 i = 0; i < songIds.length; i++) {
            Song storage song = songs[songIds[i]];
            _mint(recipient, songIds[i], quantities[i], "");
            song.currentSupply += quantities[i];
            emit SongMinted(
                songIds[i],
                recipient,
                artistAddresses[i],
                quantities[i],
                costs[i]
            );
        }

        for (uint256 i = 0; i < songIds.length; i++) {
            (bool success, ) = payable(artistAddresses[i]).call{value: costs[i]}("");
            require(success, "Artist payment failed");
        }

        if (msg.value > totalCost) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(refundSuccess, "Refund failed");
        }
    }


    function updatePlatformFee(uint256 newFee) public onlyOwner {
        require(newFee <= MAX_PLATFORM_FEE, "Fee too high");
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    function updateSongPrice(uint256 songId, uint256 newPrice) public {
        require(
            songs[songId].artist == msg.sender || owner() == msg.sender,
            "Not artist or owner"
        );
        songs[songId].price = newPrice;
        emit SongPriceUpdated(songId, newPrice);
    }

    function updateSongMetadata(
        uint256 songId,
        string memory newTitle,
        string memory newTokenUri
    ) public {
        require(songs[songId].exists, "Song does not exist");
        require(
            songs[songId].artist == msg.sender || owner() == msg.sender,
            "Not artist or owner"
        );
        require(bytes(newTitle).length > 0, "Title cannot be empty");
        require(bytes(newTokenUri).length > 0, "URI cannot be empty");

        songs[songId].title = newTitle;
        tokenUris[songId] = newTokenUri;

        emit SongMetadataUpdated(songId, newTitle, newTokenUri);
    }

    function uri(uint256 songId) public view override returns (string memory) {
        require(songs[songId].exists, "URI query for nonexistent token");
        return tokenUris[songId];
    }

    function getArtistSongs(
        address artist
    ) public view returns (uint256[] memory) {
        return artistSongs[artist];
    }

    function updateArtistAddress(uint256 songId, address newArtist) public {
        require(newArtist != address(0), "Invalid new artist address");
        Song storage song = songs[songId];
        require(song.exists, "Song does not exist");
        require(
            songs[songId].artist == msg.sender || owner() == msg.sender,
            "Not artist or owner"
        );

        address oldArtist = song.artist;
        song.artist = newArtist;

        _removeSongFromArtist(oldArtist, songId);

        artistSongs[newArtist].push(songId);

        emit ArtistAddressChanged(songId, oldArtist, newArtist);
    }

    function _removeSongFromArtist(address artist, uint256 songId) private {
        uint256[] storage songsOfArtist = artistSongs[artist];
        for (uint256 i = 0; i < songsOfArtist.length; i++) {
            if (songsOfArtist[i] == songId) {
                songsOfArtist[i] = songsOfArtist[songsOfArtist.length - 1];
                songsOfArtist.pop();
                break;
            }
        }
    }

    function pause() public onlyOwner {
        _pause();
        emit ContractPaused(owner());
    }

    function unpause() public onlyOwner {
        _unpause();
        emit ContractUnpaused(owner());
    }

    function withdrawPlatformFees() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Platform fee withdrawal failed");
        
        emit PlatformFeesWithdrawn(owner(), balance);
    }

    function getSongDetails(
        uint256 songId
    )
        public
        view
        returns (
            string memory title,
            address artist,
            uint256 price,
            uint256 maxSupply,
            uint256 currentSupply,
            bool exists
        )
    {
        Song storage song = songs[songId];
        require(song.exists, "Song does not exist");
        return (
            song.title,
            song.artist,
            song.price,
            song.maxSupply,
            song.currentSupply,
            song.exists
        );
    }

    /**
     * @dev Recover tokens accidentally sent to this contract
     * @param tokenAddress The address of the token to recover
     * @param tokenAmount Amount of tokens to recover
     */
    function recoverTokens(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner nonReentrant {
        require(tokenAddress != address(0), "Invalid token address");
        require(tokenAmount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(tokenAddress);
        require(
            token.balanceOf(address(this)) >= tokenAmount,
            "Insufficient token balance"
        );

        bool success = token.transfer(owner(), tokenAmount);
        require(success, "Token transfer failed");

        emit TokensRecovered(tokenAddress, owner(), tokenAmount);
    }
}
