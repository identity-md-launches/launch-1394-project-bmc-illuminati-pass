// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {StandardArt} from "../src/StandardArt.sol";
import {MysteryDraw} from "../src/MysteryDraw.sol";
import {MockBMC, FakeBurnBMC, SixDecimalBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";
import {DeployBMCIlluminatiPass} from "../script/Deploy.s.sol";

contract Reenterer is IERC721Receiver {
    BMCIlluminatiPass public pass;
    bool public attackGenesis;
    uint256 public attempts;
    bytes public lastRevert;

    constructor(BMCIlluminatiPass p) {
        pass = p;
    }

    function setAttackGenesis(bool v) external {
        attackGenesis = v;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        attempts++;
        if (attackGenesis) {
            try pass.mintGenesis() {}
            catch (bytes memory reason) {
                lastRevert = reason;
                revert("reentered");
            }
        } else {
            try pass.mintMystery() {}
            catch (bytes memory reason) {
                lastRevert = reason;
                revert("reentered");
            }
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract BMCIlluminatiPassTest is Test {
    MockBMC bmc;
    MockVRFCoordinator vrf;
    BMCIlluminatiPass pass;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant GENESIS_PRICE = 1_000_000e18;
    uint256 constant MYSTERY_PRICE = 350_000e18;
    uint256 constant SUB_ID = 27852459484169864437638942739291618120641810244677084392617474192083559562985;
    bytes32 constant KEY_HASH = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;
    string constant CID = "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    function setUp() public {
        vm.warp(1_760_000_000);
        bmc = new MockBMC();
        vrf = new MockVRFCoordinator();
        pass = new BMCIlluminatiPass(owner, address(bmc), address(vrf), SUB_ID);
    }

    // ------------------------------------------------------------------ helpers

    function _fund(address who, uint256 amount) internal {
        bmc.mint(who, amount);
    }

    function _mintGenesisAs(address who) internal returns (uint256 id) {
        _fund(who, GENESIS_PRICE);
        vm.startPrank(who);
        bmc.approve(address(pass), GENESIS_PRICE);
        id = pass.mintGenesis();
        vm.stopPrank();
    }

    function _mintMysteryAs(address who) internal returns (uint256 id) {
        _fund(who, MYSTERY_PRICE);
        vm.startPrank(who);
        bmc.approve(address(pass), MYSTERY_PRICE);
        id = pass.mintMystery();
        vm.stopPrank();
    }

    function _finishPhase1() internal {
        for (uint256 i = 0; i < 40; i++) {
            _mintGenesisAs(address(uint160(0x1000 + i)));
        }
        assertEq(pass.totalMinted(), 40);
    }

    function _closeSaleByIdle() internal {
        vm.warp(block.timestamp + pass.SALE_IDLE_TIMEOUT());
        assertTrue(pass.saleClosed());
    }

    function _deliverSeed(uint256 word) internal returns (uint256 req) {
        req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, word));
        assertTrue(pass.seedSet());
    }

    function _decodeTokenURI(uint256 id) internal view returns (string memory) {
        string memory uri = pass.tokenURI(id);
        bytes memory b = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory payload = new bytes(b.length - prefix.length);
        for (uint256 i = 0; i < payload.length; i++) {
            payload[i] = b[i + prefix.length];
        }
        return string(_b64decode(payload));
    }

    function _b64decode(bytes memory data) internal pure returns (bytes memory out) {
        bytes memory table = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
        uint8[256] memory rev;
        for (uint8 i = 0; i < 64; i++) {
            rev[uint8(table[i])] = i;
        }
        uint256 len = data.length;
        uint256 pad;
        if (len > 0 && data[len - 1] == "=") pad++;
        if (len > 1 && data[len - 2] == "=") pad++;
        out = new bytes((len / 4) * 3 - pad);
        uint256 o;
        for (uint256 i = 0; i < len; i += 4) {
            uint256 n = (uint256(rev[uint8(data[i])]) << 18) | (uint256(rev[uint8(data[i + 1])]) << 12)
                | (uint256(rev[uint8(data[i + 2])]) << 6) | uint256(rev[uint8(data[i + 3])]);
            if (o < out.length) out[o++] = bytes1(uint8(n >> 16));
            if (o < out.length) out[o++] = bytes1(uint8(n >> 8));
            if (o < out.length) out[o++] = bytes1(uint8(n));
        }
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i = 0; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ deployment / config

    function test_DeployScriptConfig() public {
        DeployBMCIlluminatiPass d = new DeployBMCIlluminatiPass();
        DeployBMCIlluminatiPass.Config memory cfg = d.mainnetConfig(owner);
        assertEq(cfg.bmc, 0x38224239f2BDae357D47cb864BC533d7f72dF961);
        assertEq(cfg.vrfCoordinator, 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a);
        assertEq(cfg.subscriptionId, SUB_ID);
        BMCIlluminatiPass p = d.deploy(cfg);
        assertEq(p.owner(), owner);
        assertEq(address(p.BMC()), cfg.bmc);
        assertEq(address(p.VRF_COORDINATOR()), cfg.vrfCoordinator);
        assertEq(p.SUBSCRIPTION_ID(), SUB_ID);
        assertEq(p.name(), "BMC Illuminati Pass");
        assertEq(p.symbol(), "BMCPASS");
        // Fully configured at construction: no owner call is needed before the first mint.
        assertEq(p.genesisImagesCID(), CID);
        assertEq(p.KEY_HASH(), KEY_HASH);
        assertEq(p.CALLBACK_GAS_LIMIT(), 500_000);
        assertEq(p.REQUEST_CONFIRMATIONS(), 3);
        assertTrue(p.NATIVE_PAYMENT());
    }

    function test_ConstructorMakesNoExternalCall() public {
        // Addresses without code: the launch rehearses constructors on an empty chain.
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(0x1234), address(0x5678), 1);
        assertEq(address(p.BMC()), address(0x1234));
        assertEq(p.owner(), owner);
    }

    function test_ConstructorRejectsZeroArguments() public {
        vm.expectRevert(bytes("zero argument"));
        new BMCIlluminatiPass(owner, address(0), address(vrf), SUB_ID);
        vm.expectRevert(bytes("zero argument"));
        new BMCIlluminatiPass(owner, address(bmc), address(0), SUB_ID);
        vm.expectRevert(bytes("zero argument"));
        new BMCIlluminatiPass(owner, address(bmc), address(vrf), 0);
        vm.expectRevert();
        new BMCIlluminatiPass(address(0), address(bmc), address(vrf), SUB_ID);
    }

    function test_DeployScriptRequiresOwner() public {
        DeployBMCIlluminatiPass d = new DeployBMCIlluminatiPass();
        DeployBMCIlluminatiPass.Config memory cfg = d.mainnetConfig(address(0));
        vm.expectRevert(bytes("owner required"));
        d.deploy(cfg);
    }

    function test_Constants() public view {
        assertEq(pass.MAX_SUPPLY(), 500);
        assertEq(pass.GENESIS_PHASE_SUPPLY(), 40);
        assertEq(pass.MYSTERY_SUPPLY(), 460);
        assertEq(pass.TOTAL_GENESIS(), 77);
        assertEq(pass.MYSTERY_GENESIS(), 37);
        assertEq(pass.TOTAL_STANDARD(), 423);
        assertEq(pass.GENESIS_PRICE(), GENESIS_PRICE);
        assertEq(pass.MYSTERY_PRICE(), MYSTERY_PRICE);
        assertEq(pass.MAX_TOTAL_BURN(), 201_000_000e18);
        assertEq(40 * GENESIS_PRICE + 460 * MYSTERY_PRICE, pass.MAX_TOTAL_BURN());
        assertEq(pass.SALE_IDLE_TIMEOUT(), 30 days);
        assertEq(pass.SEED_REQUEST_TIMEOUT(), 36 hours);
        assertGt(pass.SEED_REQUEST_TIMEOUT(), 24 hours, "longer than Chainlink's pending window");
        assertEq(pass.GENESIS_IMAGES_CID(), CID);
    }

    function test_NoOwnerConfigurationSurface() public {
        // The owner has no on-chain power: these selectors from the previous design no longer exist.
        (bool ok,) = address(pass).call(abi.encodeWithSignature("setGenesisImagesCID(string)", "x"));
        assertFalse(ok);
        (ok,) = address(pass)
            .call(
                abi.encodeWithSignature(
                    "setVRFConfig(uint256,bytes32,uint32,uint16,bool)", 1, KEY_HASH, 500_000, 3, true
                )
            );
        assertFalse(ok);
        (ok,) = address(pass).call(abi.encodeWithSignature("setCoordinator(address)", address(1)));
        assertFalse(ok);
        vm.startPrank(owner);
        vm.expectRevert();
        pass.mintGenesis(); // no allowance / balance: owner pays like anyone else
        vm.stopPrank();
        assertEq(pass.totalMinted(), 0);
    }

    // ------------------------------------------------------------------ phase 1

    function test_FirstMinterGetsLegendaryGenesis1() public {
        uint256 id = _mintGenesisAs(alice);
        assertEq(id, 1);
        assertEq(pass.ownerOf(1), alice);
        assertEq(uint8(pass.tierOf(1)), uint8(BMCIlluminatiPass.Tier.LegendaryGenesis));
        assertEq(pass.artworkIdOf(1), 1);
        assertEq(uint8(pass.revealStatusOf(1)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        string memory json = _decodeTokenURI(1);
        assertTrue(_contains(json, '"Legendary Genesis"'));
        assertTrue(_contains(json, string.concat("ipfs://", CID, "/genesis-01.png")));
        assertTrue(_contains(json, "Legendary Golden Crown"));
    }

    function test_Mints2To40AreSequentialGenesis() public {
        _mintGenesisAs(alice);
        for (uint256 i = 2; i <= 40; i++) {
            address who = address(uint160(0x3000 + i));
            uint256 id = _mintGenesisAs(who);
            assertEq(id, i);
            assertEq(pass.ownerOf(i), who);
            assertEq(uint8(pass.tierOf(i)), uint8(BMCIlluminatiPass.Tier.Genesis));
            assertEq(pass.artworkIdOf(i), uint16(i));
        }
        string memory json = _decodeTokenURI(7);
        assertTrue(_contains(json, "/genesis-07.png"));
        assertTrue(_contains(json, '{"trait_type":"Tier","value":"Genesis"}'));
        assertFalse(_contains(json, "Legendary"));
        json = _decodeTokenURI(40);
        assertTrue(_contains(json, "/genesis-40.png"));
        assertEq(pass.totalMinted(), 40);
        assertFalse(pass.genesisPhaseActive());
        assertEq(pass.totalBurned(), 40 * GENESIS_PRICE);
    }

    function test_Phase1CostsExactlyOneMillion() public {
        _fund(alice, 5_000_000e18);
        uint256 supplyBefore = bmc.totalSupply();
        vm.startPrank(alice);
        bmc.approve(address(pass), GENESIS_PRICE);
        pass.mintGenesis();
        vm.stopPrank();
        assertEq(bmc.balanceOf(alice), 4_000_000e18);
        assertEq(bmc.totalSupply(), supplyBefore - GENESIS_PRICE, "tokens destroyed, not moved");
        assertEq(bmc.balanceOf(address(pass)), 0);
        assertEq(bmc.allowance(alice, address(pass)), 0);
        assertEq(pass.totalBurned(), GENESIS_PRICE);
        assertEq(pass.currentPrice(), GENESIS_PRICE);
    }

    function test_GenesisRevertsAfterPhase1() public {
        _finishPhase1();
        _fund(alice, GENESIS_PRICE);
        vm.startPrank(alice);
        bmc.approve(address(pass), GENESIS_PRICE);
        vm.expectRevert(BMCIlluminatiPass.GenesisPhaseOver.selector);
        pass.mintGenesis();
        vm.stopPrank();
    }

    function test_MysteryRevertsDuringPhase1() public {
        _mintGenesisAs(alice);
        _fund(bob, MYSTERY_PRICE);
        vm.startPrank(bob);
        bmc.approve(address(pass), MYSTERY_PRICE);
        vm.expectRevert(BMCIlluminatiPass.GenesisPhaseNotOver.selector);
        pass.mintMystery();
        vm.stopPrank();
    }

    function test_GenesisPhaseNeverClosesByIdleTime() public {
        _mintGenesisAs(alice);
        vm.warp(block.timestamp + 400 days);
        assertFalse(pass.saleClosed());
        assertEq(pass.seedRequestAvailableAt(), 0);
        uint256 id = _mintGenesisAs(bob);
        assertEq(id, 2);
    }

    // ------------------------------------------------------------------ burn / allowance failures

    function test_RevertNoAllowance() public {
        _fund(alice, GENESIS_PRICE);
        vm.prank(alice);
        vm.expectRevert();
        pass.mintGenesis();
        assertEq(pass.totalMinted(), 0);
        assertEq(bmc.balanceOf(alice), GENESIS_PRICE);
    }

    function test_RevertInsufficientAllowance() public {
        _fund(alice, GENESIS_PRICE);
        vm.startPrank(alice);
        bmc.approve(address(pass), GENESIS_PRICE - 1);
        vm.expectRevert();
        pass.mintGenesis();
        vm.stopPrank();
        assertEq(pass.totalMinted(), 0);
    }

    function test_RevertInsufficientBalance() public {
        _fund(alice, GENESIS_PRICE - 1);
        vm.startPrank(alice);
        bmc.approve(address(pass), GENESIS_PRICE);
        vm.expectRevert();
        pass.mintGenesis();
        vm.stopPrank();
        assertEq(pass.totalMinted(), 0);
        assertEq(pass.totalBurned(), 0);
    }

    function test_ExcessAllowanceOnlyBurnsPrice() public {
        _fund(alice, 10_000_000e18);
        vm.startPrank(alice);
        bmc.approve(address(pass), 10_000_000e18);
        pass.mintGenesis();
        vm.stopPrank();
        assertEq(bmc.balanceOf(alice), 9_000_000e18);
        assertEq(bmc.allowance(alice, address(pass)), 9_000_000e18);
    }

    function test_RevertWhenTokenDoesNotActuallyBurn() public {
        FakeBurnBMC fake = new FakeBurnBMC();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(fake), address(vrf), SUB_ID);
        fake.mint(alice, GENESIS_PRICE);
        vm.startPrank(alice);
        fake.approve(address(p), GENESIS_PRICE);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.BurnMismatch.selector, GENESIS_PRICE, 0));
        p.mintGenesis();
        vm.stopPrank();
    }

    function test_RevertWhenTokenDecimalsUnexpected() public {
        SixDecimalBMC six = new SixDecimalBMC();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(six), address(vrf), SUB_ID);
        six.mint(alice, GENESIS_PRICE);
        vm.startPrank(alice);
        six.approve(address(p), GENESIS_PRICE);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.UnexpectedTokenDecimals.selector, uint8(6)));
        p.mintGenesis();
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ reentrancy

    function test_ReentrancyGenesisBlocked() public {
        Reenterer r = new Reenterer(pass);
        r.setAttackGenesis(true);
        _fund(address(r), 2 * GENESIS_PRICE);
        vm.prank(address(r));
        bmc.approve(address(pass), 2 * GENESIS_PRICE);
        vm.prank(address(r));
        vm.expectRevert(bytes("reentered"));
        pass.mintGenesis();
        assertEq(pass.totalMinted(), 0);
        assertEq(pass.totalBurned(), 0);
        assertEq(bmc.balanceOf(address(r)), 2 * GENESIS_PRICE);
    }

    function test_ReentrancyMysteryBlocked() public {
        _finishPhase1();
        Reenterer r = new Reenterer(pass);
        r.setAttackGenesis(false);
        _fund(address(r), 2 * MYSTERY_PRICE);
        vm.prank(address(r));
        bmc.approve(address(pass), 2 * MYSTERY_PRICE);
        vm.prank(address(r));
        vm.expectRevert(bytes("reentered"));
        pass.mintMystery();
        assertEq(pass.totalMinted(), 40);
        assertEq(bmc.balanceOf(address(r)), 2 * MYSTERY_PRICE);
        assertEq(r.attempts(), 0, "outer revert rolled back the receiver state too");
    }

    // ------------------------------------------------------------------ phase 2

    function test_Phase2CostsExactly350kAndMakesNoVRFRequest() public {
        _finishPhase1();
        _fund(alice, 1_000_000e18);
        uint256 supplyBefore = bmc.totalSupply();
        vm.startPrank(alice);
        bmc.approve(address(pass), MYSTERY_PRICE);
        uint256 id = pass.mintMystery();
        vm.stopPrank();
        assertEq(id, 41);
        assertEq(pass.ownerOf(41), alice);
        assertEq(bmc.balanceOf(alice), 650_000e18);
        assertEq(bmc.totalSupply(), supplyBefore - MYSTERY_PRICE);
        assertEq(pass.totalBurned(), 40 * GENESIS_PRICE + MYSTERY_PRICE);
        assertEq(uint8(pass.tierOf(41)), uint8(BMCIlluminatiPass.Tier.Pending));
        assertEq(uint8(pass.revealStatusOf(41)), uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));
        assertEq(pass.pendingReveals(), 1);
        assertEq(pass.remainingMysteryMints(), 459);
        assertEq(pass.currentPrice(), MYSTERY_PRICE);
        assertEq(vrf.requestCount(), 0, "a mint never opens a VRF request");
        // A mint's success does not depend on the coordinator at all.
        vrf.setRejectRequests(true);
        assertEq(_mintMysteryAs(bob), 42);
    }

    function test_PendingMetadataIsNeutral() public {
        _finishPhase1();
        uint256 id = _mintMysteryAs(alice);
        string memory json = _decodeTokenURI(id);
        assertTrue(_contains(json, "Pending Reveal"));
        assertFalse(_contains(json, "genesis-"));
        assertFalse(_contains(json, '"Standard"'));
        assertFalse(_contains(json, '"Genesis"'));
        assertEq(pass.artworkIdOf(id), 0);
        vm.expectRevert(bytes("not standard"));
        pass.standardSVG(id);
    }

    function test_PendingTokenIsTransferable() public {
        _finishPhase1();
        uint256 id = _mintMysteryAs(alice);
        vm.prank(alice);
        pass.transferFrom(alice, bob, id);
        assertEq(pass.ownerOf(id), bob);
    }

    // ------------------------------------------------------------------ sale close rules

    function test_SaleClosesWhenSoldOut() public {
        _finishPhase1();
        for (uint256 i = 0; i < 460; i++) {
            _mintMysteryAs(address(uint160(0x5000 + (i % 97))));
        }
        assertTrue(pass.saleClosed());
        assertEq(pass.seedRequestAvailableAt(), block.timestamp);
        assertEq(pass.currentPrice(), 0);
        assertEq(pass.remainingMysteryMints(), 0);
        _fund(alice, GENESIS_PRICE);
        vm.startPrank(alice);
        bmc.approve(address(pass), GENESIS_PRICE);
        vm.expectRevert(BMCIlluminatiPass.SoldOut.selector);
        pass.mintMystery();
        vm.expectRevert(BMCIlluminatiPass.GenesisPhaseOver.selector);
        pass.mintGenesis();
        vm.stopPrank();
    }

    function test_SaleClosesAfterIdleTimeoutAndEveryMintResetsIt() public {
        _finishPhase1();
        uint256 t0 = block.timestamp;
        assertEq(pass.lastMintAt(), t0);
        assertEq(pass.seedRequestAvailableAt(), 0, "no mystery token yet: the close time cannot be predicted");
        vm.warp(t0 + 30 days - 1);
        assertFalse(pass.saleClosed());
        _mintMysteryAs(alice); // the first mystery mint starts the idle clock
        uint256 t1 = block.timestamp;
        assertEq(pass.seedRequestAvailableAt(), t1 + 30 days);
        vm.warp(t0 + 30 days);
        assertFalse(pass.saleClosed(), "mint one second before the deadline keeps the sale open");
        vm.warp(t1 + 30 days - 1);
        assertFalse(pass.saleClosed());
        vm.warp(t1 + 30 days);
        assertTrue(pass.saleClosed());
        assertEq(pass.currentPrice(), 0);
        assertEq(pass.remainingMysteryMints(), 0);
        _fund(bob, MYSTERY_PRICE);
        vm.startPrank(bob);
        bmc.approve(address(pass), MYSTERY_PRICE);
        vm.expectRevert(BMCIlluminatiPass.SaleIsClosed.selector);
        pass.mintMystery();
        vm.stopPrank();
        assertEq(bmc.balanceOf(bob), MYSTERY_PRICE, "nothing burned after close");
        assertEq(pass.totalMinted(), 41);
    }

    function test_SeedRequestRevertsWhileSaleOpen() public {
        _finishPhase1();
        _mintMysteryAs(alice);
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        pass.requestSeed();
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        pass.requestSeedWith(SUB_ID, KEY_HASH);
        assertEq(vrf.requestCount(), 0);
    }

    /// @dev The idle clock does not start at the 40th Genesis mint: with no mystery token the sale
    ///      cannot close, nothing can be requested, and the first mystery mint is still possible after
    ///      any gap. A closed sale therefore always has something to reveal.
    function test_IdleTimeDoesNotCloseTheSaleBeforeTheFirstMysteryMint() public {
        _finishPhase1();
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 400 days);
        assertFalse(pass.saleClosed());
        assertEq(pass.seedRequestAvailableAt(), 0, "the view promises nothing while no request can succeed");
        assertEq(pass.currentPrice(), MYSTERY_PRICE);
        assertEq(pass.remainingMysteryMints(), 460);
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        pass.requestSeed();
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        pass.requestSeedWith(SUB_ID, KEY_HASH);
        assertEq(vrf.requestCount(), 0);
        assertEq(pass.finalizeReveals(10), 0);

        // The mystery phase starts whenever the first buyer arrives; its mint starts the clock.
        uint256 id = _mintMysteryAs(alice);
        assertEq(id, 41);
        uint256 t1 = block.timestamp;
        assertEq(pass.seedRequestAvailableAt(), t1 + 30 days);
        vm.warp(t1 + 30 days - 1);
        assertFalse(pass.saleClosed());
        vm.warp(t1 + 30 days);
        assertTrue(pass.saleClosed());
        assertEq(pass.seedRequestAvailableAt(), t1 + 30 days);
        pass.requestSeed();
    }

    // ------------------------------------------------------------------ seed and reveal

    function test_SeedRequestUsesConfiguredParameters() public {
        _finishPhase1();
        _mintMysteryAs(alice);
        _closeSaleByIdle();
        vm.prank(bob); // permissionless
        uint256 req = pass.requestSeed();
        (address consumer, uint32 gas,, bytes32 kh, uint256 sub, uint16 conf, bool native) = vrf.requests(req);
        assertEq(consumer, address(pass));
        assertEq(gas, 500_000);
        assertEq(kh, KEY_HASH);
        assertEq(sub, SUB_ID);
        assertEq(conf, 3);
        assertTrue(native);
        assertTrue(pass.isSeedRequest(req));
        assertEq(pass.seedRequestCount(), 1);
        assertEq(pass.lastSeedRequestAt(), block.timestamp);
        assertFalse(pass.seedSet());
    }

    function test_SeedDeliveryFinalizesMetadataInTheSameTransaction() public {
        _finishPhase1();
        uint256 a = _mintMysteryAs(alice);
        uint256 b = _mintMysteryAs(bob);
        _closeSaleByIdle();
        uint256 req = _deliverSeed(123456789);
        assertEq(pass.seed(), 123456789);
        assertEq(pass.seedRequestId(), req);
        // Outcomes are final and visible with no materialization step and no public-but-pending window.
        for (uint256 id = a; id <= b; id++) {
            assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.RandomnessStored));
            BMCIlluminatiPass.Tier t = pass.tierOf(id);
            assertTrue(t == BMCIlluminatiPass.Tier.Genesis || t == BMCIlluminatiPass.Tier.Standard);
            uint16 art = pass.artworkIdOf(id);
            string memory json = _decodeTokenURI(id);
            assertFalse(_contains(json, "Pending"));
            if (t == BMCIlluminatiPass.Tier.Genesis) {
                assertTrue(art >= 41 && art <= 77);
                assertTrue(_contains(json, string.concat("/genesis-", vm.toString(uint256(art)), ".png")));
            } else {
                assertTrue(art >= 1 && art <= 423);
                assertTrue(_contains(json, '"Standard"'));
                assertTrue(_contains(json, "data:image/svg+xml;base64,"));
                assertTrue(_contains(pass.standardSVG(id), "</svg>"));
            }
        }
        // Materialization changes nothing visible, only the status and the counters.
        bytes32 before = keccak256(abi.encode(_decodeTokenURI(a), _decodeTokenURI(b), pass.tierOf(a), pass.tierOf(b)));
        assertEq(pass.finalizeReveals(10), 2);
        assertEq(before, keccak256(abi.encode(_decodeTokenURI(a), _decodeTokenURI(b), pass.tierOf(a), pass.tierOf(b))));
        assertEq(uint8(pass.revealStatusOf(a)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        assertEq(pass.revealedCount(), 2);
        assertEq(pass.pendingReveals(), 0);
        assertEq(pass.finalizeReveals(10), 0, "nothing left");
    }

    function test_RedeliveryAndSecondRequestCannotReroll() public {
        _finishPhase1();
        uint256 a = _mintMysteryAs(alice);
        _closeSaleByIdle();
        uint256 req = _deliverSeed(1);
        bytes32 h = keccak256(abi.encode(pass.tierOf(a), pass.artworkIdOf(a), _decodeTokenURI(a)));
        // Re-delivery of the same request is ignored.
        vm.expectEmit(true, false, false, true);
        emit BMCIlluminatiPass.SeedDeliveryIgnored(req, 2);
        assertTrue(vrf.redeliver(req, 2));
        assertEq(pass.seed(), 1);
        // No new request is possible once the seed is set.
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(BMCIlluminatiPass.SeedAlreadyDelivered.selector);
        pass.requestSeed();
        vm.expectRevert(BMCIlluminatiPass.SeedAlreadyDelivered.selector);
        pass.requestSeedWith(SUB_ID, KEY_HASH);
        assertEq(h, keccak256(abi.encode(pass.tierOf(a), pass.artworkIdOf(a), _decodeTokenURI(a))));
    }

    function test_OnlyCoordinatorCanFulfill() public {
        _finishPhase1();
        _mintMysteryAs(alice);
        _closeSaleByIdle();
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.prank(alice);
        vm.expectRevert(BMCIlluminatiPass.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(req, words);
        vm.prank(owner);
        vm.expectRevert(BMCIlluminatiPass.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(req, words);
        vm.prank(address(vrf));
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.UnknownRequest.selector, 999_999));
        pass.rawFulfillRandomWords(999_999, words);
        vm.prank(address(vrf));
        vm.expectRevert(BMCIlluminatiPass.NoRandomWords.selector);
        pass.rawFulfillRandomWords(req, new uint256[](0));
        assertFalse(pass.seedSet());
    }

    function test_CallbackGasIsFarBelowLimit() public {
        _finishPhase1();
        _mintMysteryAs(alice);
        _closeSaleByIdle();
        uint256 req = pass.requestSeed();
        // A callback that only stores the seed fits in a fraction of the 500,000 gas limit.
        assertTrue(vrf.fulfillWithGas(req, 77, 100_000));
        assertTrue(pass.seedSet());
    }

    function test_FinalizeBeforeSeedDoesNothing() public {
        _finishPhase1();
        _mintMysteryAs(alice);
        assertEq(pass.finalizeReveals(10), 0);
        assertEq(pass.revealedCount(), 0);
    }

    function test_ViewsRevertForNonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.NonexistentToken.selector, 0));
        pass.tierOf(0);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.NonexistentToken.selector, 1));
        pass.tokenURI(1);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.NonexistentToken.selector, 501));
        pass.artworkIdOf(501);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.NonexistentToken.selector, 1));
        pass.revealStatusOf(1);
    }

    function test_TransfersAreStandard() public {
        _mintGenesisAs(alice);
        vm.prank(alice);
        pass.transferFrom(alice, bob, 1);
        assertEq(pass.ownerOf(1), bob);
        assertEq(bmc.totalSupply(), 0, "no BMC burned on transfer");
        assertEq(pass.totalBurned(), GENESIS_PRICE);
        vm.prank(bob);
        pass.safeTransferFrom(bob, alice, 1);
        assertEq(pass.ownerOf(1), alice);
    }

    // ------------------------------------------------------------------ full mint-out

    function test_Full500MintSimulation() public {
        _finishPhase1();
        for (uint256 i = 0; i < 460; i++) {
            address who = address(uint160(0x5000 + (i % 97)));
            uint256 id = _mintMysteryAs(who);
            assertEq(id, 41 + i);
            assertEq(uint8(pass.tierOf(id)), uint8(BMCIlluminatiPass.Tier.Pending));
        }
        assertEq(pass.totalMinted(), 500);
        assertEq(pass.remainingSupply(), 0);
        assertEq(pass.pendingReveals(), 460);
        assertEq(pass.currentPrice(), 0);
        assertTrue(pass.saleClosed());
        assertEq(vrf.requestCount(), 0);

        // One request, one word, every outcome final.
        _deliverSeed(uint256(keccak256("the one seed")));
        assertEq(vrf.requestCount(), 1);

        // Views agree before and after materialization, in any batch size.
        BMCIlluminatiPass.Tier[501] memory tierBefore;
        uint16[501] memory artBefore;
        for (uint256 id = 41; id <= 500; id++) {
            tierBefore[id] = pass.tierOf(id);
            artBefore[id] = pass.artworkIdOf(id);
        }
        uint256 batch = 1;
        while (pass.finalizeReveals(batch) != 0) {
            batch = batch * 3 + 1;
        }
        assertEq(pass.revealedCount(), 460);
        assertEq(pass.pendingReveals(), 0);
        assertEq(pass.remainingMysteryGenesis(), 0);
        assertEq(pass.remainingMysteryStandard(), 0);

        // Tally: 77 Genesis, 423 Standard, no duplicate artwork, no tier inferable from id.
        uint256 genesis;
        uint256 standard;
        bool[78] memory genesisSeen;
        bool[424] memory standardSeen;
        for (uint256 id = 1; id <= 500; id++) {
            BMCIlluminatiPass.Tier t = pass.tierOf(id);
            uint16 art = pass.artworkIdOf(id);
            if (id > 40) {
                assertEq(uint8(t), uint8(tierBefore[id]), "tier changed by materialization");
                assertEq(art, artBefore[id], "artwork changed by materialization");
                assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
            }
            if (t == BMCIlluminatiPass.Tier.LegendaryGenesis) {
                assertEq(id, 1);
                assertEq(art, 1);
                genesis++;
                genesisSeen[1] = true;
            } else if (t == BMCIlluminatiPass.Tier.Genesis) {
                assertTrue(art >= 2 && art <= 77, "genesis art range");
                assertFalse(genesisSeen[art], "duplicate genesis artwork");
                genesisSeen[art] = true;
                genesis++;
                if (id <= 40) assertEq(art, id);
                else assertTrue(art >= 41);
            } else if (t == BMCIlluminatiPass.Tier.Standard) {
                assertTrue(id > 40);
                assertTrue(art >= 1 && art <= 423, "standard art range");
                assertFalse(standardSeen[art], "duplicate standard artwork");
                standardSeen[art] = true;
                standard++;
            } else {
                revert("pending token after full reveal");
            }
        }
        assertEq(genesis, 77);
        assertEq(standard, 423);
        for (uint256 g = 1; g <= 77; g++) {
            assertTrue(genesisSeen[g], "genesis artwork never assigned");
        }
        for (uint256 s = 1; s <= 423; s++) {
            assertTrue(standardSeen[s], "standard artwork never assigned");
        }
        assertEq(pass.mysteryGenesisRevealed(), 37);
        assertEq(pass.totalBurned(), 201_000_000e18);
        assertEq(pass.totalBurned(), pass.MAX_TOTAL_BURN());
        assertEq(bmc.totalSupply(), 0, "every BMC paid was destroyed");
    }

    function test_PartialSaleStillDrawsFromTheFullPool() public {
        // 100 mystery tokens sold, sale closes by idle time: each token is step i of the same draw.
        _finishPhase1();
        for (uint256 i = 0; i < 100; i++) {
            _mintMysteryAs(alice);
        }
        _closeSaleByIdle();
        uint256 s = uint256(keccak256("partial"));
        _deliverSeed(s);
        for (uint256 i = 0; i < 100; i++) {
            (bool genesis, uint16 art) = MysteryDraw.decode(MysteryDraw.slotAt(s, i));
            assertEq(pass.artworkIdOf(41 + i), art);
            assertEq(pass.tierOf(41 + i) == BMCIlluminatiPass.Tier.Genesis, genesis);
        }
        assertEq(pass.finalizeReveals(500), 100);
        assertEq(pass.revealedCount(), 100);
        assertEq(pass.remainingMysteryGenesis() + pass.remainingMysteryStandard(), 360);
    }

    // ------------------------------------------------------------------ standard art

    function test_StandardArtCombinationsUnique() public pure {
        bool[5400] memory seen;
        for (uint256 i = 1; i <= 423; i++) {
            uint256 c = StandardArt.comboIndex(i);
            assertFalse(seen[c], "duplicate combination");
            seen[c] = true;
            StandardArt.Traits memory t = StandardArt.traitsOf(i);
            assertTrue(t.background < 6 && t.cloak < 5 && t.eyes < 6 && t.symbol < 5 && t.accessory < 6);
        }
    }

    function test_StandardArtCoversEveryTrait() public pure {
        bool[6] memory bg;
        bool[5] memory cl;
        bool[6] memory ey;
        bool[5] memory sy;
        bool[6] memory ac;
        for (uint256 i = 1; i <= 423; i++) {
            StandardArt.Traits memory t = StandardArt.traitsOf(i);
            bg[t.background] = true;
            cl[t.cloak] = true;
            ey[t.eyes] = true;
            sy[t.symbol] = true;
            ac[t.accessory] = true;
        }
        for (uint256 i = 0; i < 6; i++) {
            assertTrue(bg[i]);
            assertTrue(ey[i]);
            assertTrue(ac[i]);
        }
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(cl[i]);
            assertTrue(sy[i]);
        }
    }

    function test_StandardArtRendersWithoutGenesisTraits() public pure {
        for (uint256 i = 1; i <= 423; i += 47) {
            string memory svg = StandardArt.render(i);
            assertTrue(_contains(svg, "<svg"));
            assertTrue(_contains(svg, "</svg>"));
            assertFalse(_contains(svg, "#ffd700"));
            assertFalse(_contains(svg, "#d4af37"));
            assertFalse(_contains(svg, "gold"));
            assertFalse(_contains(svg, "triangle"));
        }
        string memory attrs = StandardArt.attributesJson(1);
        assertTrue(_contains(attrs, '"trait_type":"Background"'));
        assertFalse(_contains(attrs, "Third Eye"));
    }

    function test_StandardMetadataAfterReveal() public {
        _finishPhase1();
        for (uint256 i = 0; i < 20; i++) {
            _mintMysteryAs(alice);
        }
        _closeSaleByIdle();
        _deliverSeed(uint256(keccak256("standard")));
        // 37/460 are Genesis, so 20 tokens contain a Standard one with overwhelming probability.
        for (uint256 id = 41; id <= 60; id++) {
            if (pass.tierOf(id) == BMCIlluminatiPass.Tier.Standard) {
                string memory json = _decodeTokenURI(id);
                uint16 art = pass.artworkIdOf(id);
                assertTrue(_contains(json, '{"trait_type":"Tier","value":"Standard"}'));
                assertTrue(_contains(json, string.concat('"value":"standard-', vm.toString(uint256(art)), '"')));
                assertTrue(_contains(json, '"trait_type":"Background"'));
                assertTrue(_contains(json, '"trait_type":"Accessory"'));
                assertFalse(_contains(json, "ipfs://"));
                string memory svg = pass.standardSVG(id);
                assertTrue(_contains(svg, "</svg>"));
                return;
            }
        }
        revert("no standard outcome in 20 draws (astronomically unlikely)");
    }

    function testFuzz_SingleRevealAlwaysInInventory(uint256 word) public {
        _finishPhase1();
        uint256 id = _mintMysteryAs(alice);
        _closeSaleByIdle();
        _deliverSeed(word);
        BMCIlluminatiPass.Tier t = pass.tierOf(id);
        uint16 art = pass.artworkIdOf(id);
        assertEq(pass.finalizeReveals(1), 1);
        assertEq(uint8(pass.tierOf(id)), uint8(t));
        assertEq(pass.artworkIdOf(id), art);
        if (t == BMCIlluminatiPass.Tier.Genesis) {
            assertTrue(art >= 41 && art <= 77);
            assertEq(pass.remainingMysteryGenesis(), 36);
            assertEq(pass.remainingMysteryStandard(), 423);
        } else {
            assertEq(uint8(t), uint8(BMCIlluminatiPass.Tier.Standard));
            assertTrue(art >= 1 && art <= 423);
            assertEq(pass.remainingMysteryGenesis(), 37);
            assertEq(pass.remainingMysteryStandard(), 422);
        }
    }
}
