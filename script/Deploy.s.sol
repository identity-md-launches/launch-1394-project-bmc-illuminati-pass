// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";

/// @notice Deployment script. Mainnet values are constants; `run()` reads only the owner from the
///         environment and hands a config to `deploy`, which tests call directly.
contract DeployBMCIlluminatiPass is Script {
    /// @dev BMC Illuminati token, Ethereum mainnet (verified 2026-10-12: 18 decimals, burnFrom present).
    address public constant MAINNET_BMC = 0x38224239f2BDae357D47cb864BC533d7f72dF961;
    /// @dev Chainlink VRF v2.5 coordinator, Ethereum mainnet (verified 2026-10-12: code present,
    ///      LINK() == 0x514910771AF9Ca656af840dff83E8264EcF986CA).
    address public constant MAINNET_VRF_COORDINATOR = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;

    struct Config {
        address owner;
        address bmc;
        address vrfCoordinator;
    }

    function mainnetConfig(address owner) public pure returns (Config memory) {
        return Config({owner: owner, bmc: MAINNET_BMC, vrfCoordinator: MAINNET_VRF_COORDINATOR});
    }

    function deploy(Config memory cfg) public returns (BMCIlluminatiPass pass) {
        require(cfg.owner != address(0), "owner required");
        pass = new BMCIlluminatiPass(cfg.owner, cfg.bmc, cfg.vrfCoordinator);
    }

    /// @dev OWNER must be set in the environment. Never broadcast without explicit authorization.
    function run() external returns (BMCIlluminatiPass pass) {
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast();
        pass = deploy(mainnetConfig(owner));
        vm.stopBroadcast();
    }
}
