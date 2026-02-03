// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {tortoise_v0_3} from "../src/tortoise_v0_3.sol";

contract DeployScript is Script {
    function run() public returns (tortoise_v0_3) {
        // Load deployment parameters from environment
        uint256 platformFee = vm.envUint("PLATFORM_FEE");
        
        console.log("=== Tortoise v0.3 Deployment ===");
        console.log("Network:", block.chainid == 8453 ? "Base Mainnet" : block.chainid == 84532 ? "Base Sepolia" : "Unknown");
        console.log("Deployer:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        console.log("Platform fee:", platformFee, "wei");
        console.log("Platform fee in ETH:", platformFee / 1e15, "* 1e-3 ETH");
        console.log("");
        
        // Check deployer has sufficient balance
        require(msg.sender.balance > 0, "Deployer has no ETH");
        
        // Start broadcast (uses keystore account provided via --account flag)
        vm.startBroadcast();
        
        // Deploy the contract
        tortoise_v0_3 tortoise = new tortoise_v0_3(platformFee);
        
        console.log("Tortoise deployed at:", address(tortoise));
        console.log("Contract owner:", tortoise.owner());
        console.log("Platform fee set to:", tortoise.platformFee());
        console.log("");
        console.log("Deployment complete!");
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Post-deployment verification  
        require(tortoise.platformFee() == platformFee, "Platform fee not set correctly");
        
        console.log("Deployment verified successfully!");
        console.log("Contract owner:", tortoise.owner());
        
        return tortoise;
    }
}

contract DeployToBaseSepolia is Script {
    function run() public returns (tortoise_v0_3) {
        console.log("=== Deploying to Base Sepolia Testnet ===");
        
        // Load deployment parameters from environment
        uint256 platformFee = vm.envUint("PLATFORM_FEE");
        
        console.log("=== Tortoise v0.3 Deployment ===");
        console.log("Network: Base Sepolia");
        console.log("Deployer:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        console.log("Platform fee:", platformFee, "wei");
        console.log("Platform fee in ETH:", platformFee / 1e15, "* 1e-3 ETH");
        console.log("");
        
        // Check deployer has sufficient balance
        require(msg.sender.balance > 0, "Deployer has no ETH");
        
        // Start broadcast
        vm.startBroadcast();
        
        // Deploy the contract
        tortoise_v0_3 tortoise = new tortoise_v0_3(platformFee);
        
        console.log("Tortoise deployed at:", address(tortoise));
        console.log("Contract owner:", tortoise.owner());
        console.log("Platform fee set to:", tortoise.platformFee());
        console.log("");
        console.log("Deployment complete!");
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Post-deployment verification  
        require(tortoise.platformFee() == platformFee, "Platform fee not set correctly");
        
        console.log("Deployment verified successfully!");
        console.log("Contract owner:", tortoise.owner());
        
        return tortoise;
    }
}

contract DeployToBaseMainnet is Script {
    function run() public returns (tortoise_v0_3) {
        console.log("=== DEPLOYING TO BASE MAINNET ===");
        console.log("WARNING: This will deploy to mainnet!");
        console.log("Make sure you have reviewed everything!");
        console.log("");
        
        // Load deployment parameters from environment
        uint256 platformFee = vm.envUint("PLATFORM_FEE");
        
        console.log("=== Tortoise v0.3 Deployment ===");
        console.log("Network: Base Mainnet");
        console.log("Deployer:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        console.log("Platform fee:", platformFee, "wei");
        console.log("Platform fee in ETH:", platformFee / 1e15, "* 1e-3 ETH");
        console.log("");
        
        // Check deployer has sufficient balance
        require(msg.sender.balance > 0, "Deployer has no ETH");
        
        // Start broadcast
        vm.startBroadcast();
        
        // Deploy the contract
        tortoise_v0_3 tortoise = new tortoise_v0_3(platformFee);
        
        console.log("Tortoise deployed at:", address(tortoise));
        console.log("Contract owner:", tortoise.owner());
        console.log("Platform fee set to:", tortoise.platformFee());
        console.log("");
        console.log("Deployment complete!");
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Post-deployment verification  
        require(tortoise.platformFee() == platformFee, "Platform fee not set correctly");
        
        console.log("Deployment verified successfully!");
        console.log("Contract owner:", tortoise.owner());
        
        return tortoise;
    }
}