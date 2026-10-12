// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";

interface IRealBMC {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IRealCoordinator {
    function s_provingKeys(bytes32 keyHash) external view returns (bool exists, uint64 maxGas);
    function s_provingKeyHashes(uint256 index) external view returns (bytes32);
    function getSubscription(uint256 subId)
        external
        view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers);
    function LINK() external view returns (address);
    function pendingRequestExists(uint256 subId) external view returns (bool);
}

/// @notice Runs against a live Ethereum mainnet fork when `MAINNET_RPC_URL` is set (or when the suite
///         is already started with `--fork-url`); skipped otherwise so `forge test` passes with an
///         empty environment. Verifies the real BMC `burnFrom` behaviour and the Chainlink VRF v2.5
///         configuration the contract is fixed to. Nothing here broadcasts or changes mainnet state.
contract BMCMainnetForkTest is Test {
    address constant BMC = 0x38224239f2BDae357D47cb864BC533d7f72dF961;
    address constant VRF = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    uint256 constant SUB_ID = 27852459484169864437638942739291618120641810244677084392617474192083559562985;
    address constant SUB_OWNER = 0x83027AD9d0D5374335086c539dADD1db983441B0;

    uint256 constant GENESIS_PRICE = 1_000_000e18;
    uint256 constant MYSTERY_PRICE = 350_000e18;

    address buyer = address(0xBEEF);
    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length != 0) {
            vm.createSelectFork(rpc);
            forked = true;
        } else {
            forked = block.chainid == 1 && BMC.code.length > 0;
        }
    }

    modifier onlyFork() {
        vm.skip(!forked);
        _;
    }

    function test_RealBMCGenesisAndMysteryBurn() public onlyFork {
        IRealBMC token = IRealBMC(BMC);
        assertEq(token.decimals(), 18);

        BMCIlluminatiPass pass = new BMCIlluminatiPass(address(this), BMC, VRF, SUB_ID);

        // Test-only balance adjustment on the local fork.
        deal(BMC, buyer, GENESIS_PRICE + MYSTERY_PRICE, true);
        uint256 supplyBefore = token.totalSupply();

        vm.startPrank(buyer);
        token.approve(address(pass), GENESIS_PRICE);
        uint256 tokenId = pass.mintGenesis();
        vm.stopPrank();

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(1), buyer);
        assertEq(pass.totalBurned(), GENESIS_PRICE);
        assertEq(token.balanceOf(buyer), MYSTERY_PRICE);
        assertEq(token.allowance(buyer, address(pass)), 0, "burnFrom spent the allowance");
        assertEq(token.totalSupply(), supplyBefore - GENESIS_PRICE, "burnFrom destroyed the tokens");

        // Same semantics at the mystery price (phase 2 reached by filling phase 1 with other buyers).
        for (uint256 i = 2; i <= 40; i++) {
            address who = address(uint160(0xA000 + i));
            deal(BMC, who, GENESIS_PRICE, true);
            vm.startPrank(who);
            token.approve(address(pass), GENESIS_PRICE);
            pass.mintGenesis();
            vm.stopPrank();
        }
        supplyBefore = token.totalSupply();
        vm.startPrank(buyer);
        token.approve(address(pass), MYSTERY_PRICE);
        tokenId = pass.mintMystery();
        vm.stopPrank();
        assertEq(tokenId, 41);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.totalSupply(), supplyBefore - MYSTERY_PRICE);
        assertEq(uint8(pass.tierOf(41)), uint8(BMCIlluminatiPass.Tier.Pending));
    }

    function test_RealCoordinatorConfigurationMatchesContract() public onlyFork {
        BMCIlluminatiPass pass = new BMCIlluminatiPass(address(this), BMC, VRF, SUB_ID);
        IRealCoordinator c = IRealCoordinator(VRF);
        assertEq(c.LINK(), LINK);
        (bool exists, uint64 maxGas) = c.s_provingKeys(pass.KEY_HASH());
        assertTrue(exists, "500 gwei lane registered on the mainnet coordinator");
        assertEq(maxGas, 500 gwei);
        bool listed;
        for (uint256 i = 0; i < 3; i++) {
            if (c.s_provingKeyHashes(i) == pass.KEY_HASH()) listed = true;
        }
        assertTrue(listed, "key hash listed in s_provingKeyHashes");
        (bool bogus,) = c.s_provingKeys(bytes32(uint256(pass.KEY_HASH()) + 1));
        assertFalse(bogus);
        (,,, address subOwner,) = c.getSubscription(SUB_ID);
        assertEq(subOwner, SUB_OWNER, "subscription exists and is owned by the launch owner");
    }

    /// @dev Full seed flow on the fork: the subscription is funded and the pass added as consumer by
    ///      pranking the subscription owner (fork-local only), then the callback is driven by pranking
    ///      the coordinator with exactly the configured callback gas limit.
    function test_RealCoordinatorAcceptsRequestAndCallbackFitsGasLimit() public onlyFork {
        BMCIlluminatiPass pass = new BMCIlluminatiPass(address(this), BMC, VRF, SUB_ID);
        for (uint256 i = 1; i <= 41; i++) {
            address who = address(uint160(0xB000 + i));
            uint256 price = i <= 40 ? GENESIS_PRICE : MYSTERY_PRICE;
            deal(BMC, who, price, true);
            vm.startPrank(who);
            IRealBMC(BMC).approve(address(pass), price);
            if (i <= 40) pass.mintGenesis();
            else pass.mintMystery();
            vm.stopPrank();
        }
        vm.warp(block.timestamp + pass.SALE_IDLE_TIMEOUT());

        // Not yet a consumer: the real coordinator rejects the request, nothing changes.
        vm.expectRevert();
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 0);

        vm.prank(SUB_OWNER);
        (bool ok,) = VRF.call(abi.encodeWithSignature("addConsumer(uint256,address)", SUB_ID, address(pass)));
        assertTrue(ok, "fork-local addConsumer");
        uint256 req = pass.requestSeed();
        assertTrue(pass.isSeedRequest(req));
        (,,,, address[] memory consumers) = IRealCoordinator(VRF).getSubscription(SUB_ID);
        assertEq(consumers.length, 1);
        assertTrue(IRealCoordinator(VRF).pendingRequestExists(SUB_ID), "request recorded on the real coordinator");

        uint256[] memory words = new uint256[](1);
        words[0] = uint256(keccak256("fork seed"));
        uint256 callbackGas = pass.CALLBACK_GAS_LIMIT();
        vm.prank(VRF);
        (ok,) = address(pass).call{gas: callbackGas}(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", req, words)
        );
        assertTrue(ok, "callback succeeds within 500,000 gas");
        assertTrue(pass.seedSet());
        assertTrue(pass.tierOf(41) != BMCIlluminatiPass.Tier.Pending);
    }
}
