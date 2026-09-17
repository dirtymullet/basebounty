// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BaseBounty} from "../src/BaseBounty.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Local/anvil: deploys MockUSDC + BaseBounty, mints demo balances.
/// @dev Sepolia/mainnet: set USDC_ADDRESS env and skip mock mint.
contract Deploy is Script {
    address constant TREASURY = 0x1d4c28113002718859D9E808D81ccD3B7763E9B8;
    // Base mainnet USDC (document only - prefer Sepolia/anvil for demos)
    address constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address usdcAddr = vm.envOr("USDC_ADDRESS", address(0));
        bool mintDemo = vm.envOr("MINT_DEMO", true);

        vm.startBroadcast(pk);

        address usdc;
        if (usdcAddr == address(0)) {
            MockUSDC mock = new MockUSDC();
            usdc = address(mock);
            if (mintDemo) {
                mock.mint(deployer, 10_000e6);
                // Anvil default accounts for UI demo
                mock.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 10_000e6);
                mock.mint(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 10_000e6);
                mock.mint(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, 10_000e6);
            }
            console2.log("MockUSDC", usdc);
        } else {
            usdc = usdcAddr;
            console2.log("Using existing USDC", usdc);
            if (usdc == BASE_MAINNET_USDC) {
                console2.log("WARNING: Base mainnet USDC - do not spend real funds in demos");
            }
        }

        BaseBounty bb = new BaseBounty(usdc, TREASURY);
        console2.log("BaseBounty", address(bb));
        console2.log("Treasury", TREASURY);
        console2.log("Deployer", deployer);

        vm.stopBroadcast();
    }
}
