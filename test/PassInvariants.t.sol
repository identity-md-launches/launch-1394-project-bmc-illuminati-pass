// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

/// @notice Drives the pass with random sequences: mints of both phases by several actors, time
///         passing, seed requests on both paths, deliveries in any order with any gas, redeliveries,
///         rogue callbacks, materialization in any batch size, transfers and owner actions. Every
///         action asserts its own pre/post conditions; ghost variables record what the contract owes.
contract PassHandler is Test {
    MockBMC public bmc;
    MockVRFCoordinator public vrf;
    BMCIlluminatiPass public pass;
    address public owner;

    bytes32 constant OTHER_LANE = 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9;
    bytes32 constant BOGUS_LANE = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10c;

    address[] public actors;

    // ghosts
    uint256 public ghostGenesisMints;
    uint256 public ghostMysteryMints;
    uint256 public ghostBmcMinted; // BMC handed to actors
    bool public ghostSaleEverClosed;
    bool public ghostSeedEverSet;
    uint256 public ghostFirstSeed;
    uint256 public ghostFirstSeedRequestId;
    uint256 public ghostMintedAtSeed;
    bytes32 public ghostOutcome41;
    bytes32 public ghostOutcomeLast;
    uint256[] public requestIds;
    uint256 public ghostLastRequestAt;
    bool public ghostRequestWhileOpen;
    bool public ghostRequestTooSoon;
    uint256 public ghostFinalizedTokens;
    mapping(uint256 artwork => bool) genesisArtSeen;
    mapping(uint256 artwork => bool) standardArtSeen;
    bool public ghostDuplicateArtwork;
    uint256 public callsMintGenesis;
    uint256 public callsMintMystery;
    uint256 public callsRequest;
    uint256 public callsFulfill;
    uint256 public callsFinalize;

    constructor(MockBMC _bmc, MockVRFCoordinator _vrf, BMCIlluminatiPass _pass, address _owner) {
        bmc = _bmc;
        vrf = _vrf;
        pass = _pass;
        owner = _owner;
        for (uint256 i = 0; i < 5; i++) {
            actors.push(address(uint160(0xA11CE000 + i)));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _outcome(uint256 tokenId) internal view returns (bytes32) {
        return keccak256(abi.encode(pass.tierOf(tokenId), pass.artworkIdOf(tokenId)));
    }

    function _fund(address who, uint256 amount) internal {
        bmc.mint(who, amount);
        ghostBmcMinted += amount;
        vm.prank(who);
        bmc.approve(address(pass), amount);
    }

    // ------------------------------------------------------------------ mints

    function mintGenesis(uint256 actorSeed, uint8 count) external {
        callsMintGenesis++;
        uint256 n = bound(uint256(count), 1, 40);
        address who = _actor(actorSeed);
        for (uint256 i = 0; i < n; i++) {
            _fund(who, pass.GENESIS_PRICE());
            uint256 mintedBefore = pass.totalMinted();
            bool allowed = mintedBefore < 40;
            vm.prank(who);
            try pass.mintGenesis() returns (uint256 id) {
                assertTrue(allowed, "genesis mint after phase 1");
                assertEq(id, mintedBefore + 1);
                assertEq(pass.ownerOf(id), who);
                assertEq(pass.lastMintAt(), block.timestamp);
                ghostGenesisMints++;
            } catch {
                assertFalse(allowed, "genesis mint refused during phase 1");
            }
        }
    }

    function mintMystery(uint256 actorSeed, uint8 count) external {
        callsMintMystery++;
        uint256 n = bound(uint256(count), 1, 120);
        address who = _actor(actorSeed);
        for (uint256 i = 0; i < n; i++) {
            _fund(who, pass.MYSTERY_PRICE());
            uint256 mintedBefore = pass.totalMinted();
            bool allowed = mintedBefore >= 40 && mintedBefore < 500 && !pass.saleClosed();
            vm.prank(who);
            try pass.mintMystery() returns (uint256 id) {
                assertTrue(allowed, "mystery mint while not allowed");
                assertEq(id, mintedBefore + 1);
                assertEq(pass.ownerOf(id), who);
                assertEq(uint8(pass.tierOf(id)), uint8(BMCIlluminatiPass.Tier.Pending));
                assertEq(vrf.requestCount(), pass.seedRequestCount(), "a mint never requests");
                ghostMysteryMints++;
            } catch {
                assertFalse(allowed, "mystery mint refused while allowed");
            }
        }
        if (pass.saleClosed()) ghostSaleEverClosed = true;
    }

    /// @dev Mints every remaining mystery token in one go (when allowed) so sold-out closes are
    ///      reached in random sequences too.
    function sellOut(uint256 actorSeed) external {
        address who = _actor(actorSeed);
        while (pass.totalMinted() >= 40 && pass.totalMinted() < 500 && !pass.saleClosed()) {
            _fund(who, pass.MYSTERY_PRICE());
            vm.prank(who);
            uint256 id = pass.mintMystery();
            assertEq(id, pass.totalMinted());
            ghostMysteryMints++;
        }
        if (pass.totalMinted() == 500) {
            assertTrue(pass.saleClosed(), "sold out closes the sale at once");
            assertEq(
                pass.seedRequestAvailableAt(),
                pass.seedSet()
                    ? 0
                    : (pass.lastSeedRequestAt() == 0
                            ? block.timestamp
                            : pass.lastSeedRequestAt() + pass.SEED_REQUEST_TIMEOUT())
            );
            ghostSaleEverClosed = true;
        }
    }

    // ------------------------------------------------------------------ time

    function warp(uint32 delta) external {
        vm.warp(block.timestamp + bound(uint256(delta), 0, 3 days));
        if (pass.saleClosed()) ghostSaleEverClosed = true;
    }

    function warpPastIdle() external {
        vm.warp(block.timestamp + pass.SALE_IDLE_TIMEOUT() + 1);
        if (pass.saleClosed()) ghostSaleEverClosed = true;
    }

    // ------------------------------------------------------------------ requests

    function requestSeed(uint256 actorSeed, uint8 path, uint256 subSeed) external {
        callsRequest++;
        address who = actorSeed % 7 == 0 ? owner : _actor(actorSeed);
        uint256 p = path % 4;
        bytes32 lane = p == 1 ? OTHER_LANE : (p == 2 ? BOGUS_LANE : pass.KEY_HASH());
        bool laneOk = p != 2;
        bool closed = pass.saleClosed();
        bool allowed = closed && pass.totalMinted() > 40 && !pass.seedSet()
            && (pass.lastSeedRequestAt() == 0
                || block.timestamp >= pass.lastSeedRequestAt() + pass.SEED_REQUEST_TIMEOUT()) && laneOk;
        uint256 countBefore = pass.seedRequestCount();
        vm.prank(who);
        if (p == 0) {
            try pass.requestSeed() returns (uint256 id) {
                _afterRequest(id, allowed, closed, countBefore);
            } catch {
                assertFalse(allowed, "request refused while allowed");
                assertEq(pass.seedRequestCount(), countBefore);
            }
        } else {
            try pass.requestSeedWith(subSeed, lane) returns (uint256 id) {
                _afterRequest(id, allowed, closed, countBefore);
            } catch {
                assertFalse(allowed, "recovery request refused while allowed");
                assertEq(pass.seedRequestCount(), countBefore);
            }
        }
    }

    function _afterRequest(uint256 id, bool allowed, bool closed, uint256 countBefore) internal {
        assertTrue(allowed, "request accepted while not allowed");
        if (!closed) ghostRequestWhileOpen = true;
        if (ghostLastRequestAt != 0 && block.timestamp < ghostLastRequestAt + pass.SEED_REQUEST_TIMEOUT()) {
            ghostRequestTooSoon = true;
        }
        ghostLastRequestAt = block.timestamp;
        assertTrue(pass.isSeedRequest(id));
        assertEq(pass.seedRequestCount(), countBefore + 1);
        assertEq(pass.lastSeedRequestAt(), block.timestamp);
        requestIds.push(id);
    }

    // ------------------------------------------------------------------ deliveries

    function fulfill(uint256 reqSeed, uint256 word, uint8 gasChoice) external {
        callsFulfill++;
        if (requestIds.length == 0) return;
        uint256 id = requestIds[reqSeed % requestIds.length];
        (,, bool fulfilled,,,,) = vrf.requests(id);
        if (fulfilled) return;
        bool wasSet = pass.seedSet();
        uint256 seedBefore = pass.seed();
        uint256 gas = gasChoice % 3 == 0 ? 20_000 : 500_000; // sometimes too little gas
        bool ok = vrf.fulfillWithGas(id, word, gas);
        if (wasSet) {
            assertEq(pass.seed(), seedBefore, "seed changed by a later delivery");
            assertEq(pass.seedRequestId(), ghostFirstSeedRequestId);
        } else if (ok) {
            assertTrue(pass.seedSet());
            assertEq(pass.seed(), word);
            assertEq(pass.seedRequestId(), id);
            assertTrue(pass.saleClosed(), "seed set while the sale is open");
            ghostSeedEverSet = true;
            ghostFirstSeed = word;
            ghostFirstSeedRequestId = id;
            ghostMintedAtSeed = pass.totalMinted();
            ghostOutcome41 = _outcome(41);
            ghostOutcomeLast = _outcome(pass.totalMinted());
        } else {
            assertFalse(pass.seedSet(), "failed callback must not set the seed");
        }
    }

    function redeliver(uint256 reqSeed, uint256 word) external {
        if (requestIds.length == 0 || !pass.seedSet()) return;
        uint256 id = requestIds[reqSeed % requestIds.length];
        uint256 seedBefore = pass.seed();
        vrf.redeliver(id, word);
        assertEq(pass.seed(), seedBefore, "redelivery changed the seed");
        assertEq(pass.seedRequestId(), ghostFirstSeedRequestId);
    }

    function rogueFulfill(uint256 actorSeed, uint256 reqSeed, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        address who = actorSeed % 5 == 0 ? owner : _actor(actorSeed);
        uint256 id = requestIds.length == 0 ? reqSeed : requestIds[reqSeed % requestIds.length];
        bool wasSet = pass.seedSet();
        uint256 seedBefore = pass.seed();
        vm.prank(who);
        try pass.rawFulfillRandomWords(id, words) {
            revert("non-coordinator delivered a word");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), BMCIlluminatiPass.OnlyCoordinator.selector);
        }
        // The coordinator itself with an id this contract never requested.
        uint256 unknown = reqSeed | (1 << 255);
        vm.prank(address(vrf));
        try pass.rawFulfillRandomWords(unknown, words) {
            revert("unknown request delivered a word");
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), BMCIlluminatiPass.UnknownRequest.selector);
        }
        assertEq(pass.seedSet(), wasSet);
        assertEq(pass.seed(), seedBefore);
    }

    // ------------------------------------------------------------------ materialization

    function finalize(uint8 maxCount) external {
        callsFinalize++;
        uint256 n = bound(uint256(maxCount), 0, 60);
        uint256 pending = pass.pendingReveals();
        uint256 first = 40 + pass.revealedCount() + 1;
        uint256 expected = pass.seedSet() ? (n < pending ? n : pending) : 0;
        bytes32[] memory before = new bytes32[](expected);
        for (uint256 i = 0; i < expected; i++) {
            before[i] = _outcome(first + i);
        }
        uint256 done = pass.finalizeReveals(n);
        assertEq(done, expected, "finalize count");
        for (uint256 i = 0; i < expected; i++) {
            uint256 id = first + i;
            assertEq(_outcome(id), before[i], "materialization changed an outcome");
            assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
            BMCIlluminatiPass.Tier t = pass.tierOf(id);
            uint16 art = pass.artworkIdOf(id);
            if (t == BMCIlluminatiPass.Tier.Genesis) {
                if (art < 41 || art > 77 || genesisArtSeen[art]) ghostDuplicateArtwork = true;
                genesisArtSeen[art] = true;
            } else if (t == BMCIlluminatiPass.Tier.Standard) {
                if (art < 1 || art > 423 || standardArtSeen[art]) ghostDuplicateArtwork = true;
                standardArtSeen[art] = true;
            } else {
                ghostDuplicateArtwork = true; // a materialized token can only be Genesis or Standard
            }
        }
        ghostFinalizedTokens += done;
    }

    // ------------------------------------------------------------------ transfers and owner

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 tokenSeed) external {
        uint256 minted = pass.totalMinted();
        if (minted == 0) return;
        uint256 id = tokenSeed % minted + 1;
        address from = pass.ownerOf(id);
        address to = _actor(toSeed);
        bytes32 before = _outcome(id);
        uint8 status = uint8(pass.revealStatusOf(id));
        address caller = fromSeed % 3 == 0 ? _actor(fromSeed) : from;
        vm.prank(caller);
        try pass.transferFrom(from, to, id) {
            assertTrue(caller == from, "transfer by a stranger");
            assertEq(pass.ownerOf(id), to);
        } catch {
            assertTrue(caller != from, "owner's transfer refused");
        }
        assertEq(_outcome(id), before, "transfer changed an outcome");
        assertEq(uint8(pass.revealStatusOf(id)), status);
        assertEq(bmc.balanceOf(address(pass)), 0);
    }

    function ownerAction(uint8 choice) external {
        address current = pass.owner();
        if (current == address(0)) return;
        uint256 c = choice % 3;
        vm.prank(current);
        if (c == 0) {
            pass.transferOwnership(_actor(choice));
        } else if (c == 1) {
            pass.renounceOwnership();
        } else {
            // The owner has no reroll: an owner-initiated second request obeys the same rules.
            bool allowed = pass.saleClosed() && pass.totalMinted() > 40 && !pass.seedSet()
                && (pass.lastSeedRequestAt() == 0
                    || block.timestamp >= pass.lastSeedRequestAt() + pass.SEED_REQUEST_TIMEOUT());
            uint256 countBefore = pass.seedRequestCount();
            try pass.requestSeed() returns (uint256 id) {
                _afterRequest(id, allowed, pass.saleClosed(), countBefore);
            } catch {
                assertFalse(allowed);
            }
        }
    }

    function requestCount() external view returns (uint256) {
        return requestIds.length;
    }
}

/// @notice Invariants over random call sequences. Run counts are set inline because foundry.toml is
///         protected.
contract PassInvariantsTest is Test {
    MockBMC bmc;
    MockVRFCoordinator vrf;
    BMCIlluminatiPass pass;
    PassHandler handler;

    address owner = makeAddr("owner");
    uint256 constant SUB_ID = 27852459484169864437638942739291618120641810244677084392617474192083559562985;

    function setUp() public {
        vm.warp(1_760_000_000);
        bmc = new MockBMC();
        vrf = new MockVRFCoordinator();
        vrf.setProvingKey(0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9, true);
        pass = new BMCIlluminatiPass(owner, address(bmc), address(vrf), SUB_ID);
        handler = new PassHandler(bmc, vrf, pass, owner);

        bytes4[] memory selectors = new bytes4[](12);
        selectors[11] = PassHandler.sellOut.selector;
        selectors[0] = PassHandler.mintGenesis.selector;
        selectors[1] = PassHandler.mintMystery.selector;
        selectors[2] = PassHandler.warp.selector;
        selectors[3] = PassHandler.warpPastIdle.selector;
        selectors[4] = PassHandler.requestSeed.selector;
        selectors[5] = PassHandler.fulfill.selector;
        selectors[6] = PassHandler.redeliver.selector;
        selectors[7] = PassHandler.rogueFulfill.selector;
        selectors[8] = PassHandler.finalize.selector;
        selectors[9] = PassHandler.transfer.selector;
        selectors[10] = PassHandler.ownerAction.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyCapAndPhaseOrder() public view {
        uint256 minted = pass.totalMinted();
        assertLe(minted, 500);
        assertEq(minted, handler.ghostGenesisMints() + handler.ghostMysteryMints());
        assertLe(handler.ghostGenesisMints(), 40);
        if (handler.ghostMysteryMints() > 0) assertEq(handler.ghostGenesisMints(), 40, "mystery before phase 1 ended");
        assertEq(pass.totalSupply(), minted);
        assertEq(pass.remainingSupply(), 500 - minted);
        assertEq(pass.genesisPhaseActive(), minted < 40);
        if (minted > 0) assertTrue(pass.ownerOf(minted) != address(0));
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BurnConservation() public view {
        uint256 owed =
            handler.ghostGenesisMints() * pass.GENESIS_PRICE() + handler.ghostMysteryMints() * pass.MYSTERY_PRICE();
        assertEq(pass.totalBurned(), owed, "burned != sum of prices of minted tokens");
        assertLe(pass.totalBurned(), pass.MAX_TOTAL_BURN());
        assertEq(bmc.totalSupply(), handler.ghostBmcMinted() - pass.totalBurned(), "BMC destroyed, not moved");
        assertEq(bmc.balanceOf(address(pass)), 0, "the pass never holds BMC");
        assertEq(bmc.balanceOf(address(0xdead)), 0);
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_GenesisPhaseTokensAreFixed() public view {
        uint256 minted = pass.totalMinted();
        if (minted >= 1) {
            assertEq(uint8(pass.tierOf(1)), uint8(BMCIlluminatiPass.Tier.LegendaryGenesis));
            assertEq(pass.artworkIdOf(1), 1);
            assertEq(uint8(pass.revealStatusOf(1)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        }
        uint256 probe = minted < 40 ? minted : 40;
        if (probe >= 2) {
            assertEq(uint8(pass.tierOf(probe)), uint8(BMCIlluminatiPass.Tier.Genesis));
            assertEq(pass.artworkIdOf(probe), uint16(probe));
            assertEq(uint8(pass.tierOf(2)), uint8(BMCIlluminatiPass.Tier.Genesis));
            assertEq(pass.artworkIdOf(2), 2);
        }
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SeedIsWriteOnceAndOnlyAfterClose() public view {
        assertEq(vrf.requestCount(), pass.seedRequestCount(), "every coordinator request is accounted");
        assertEq(handler.requestCount(), pass.seedRequestCount());
        assertFalse(handler.ghostRequestWhileOpen(), "a request was made while the sale was open");
        assertFalse(handler.ghostRequestTooSoon(), "requests closer than the timeout");
        if (pass.seedRequestCount() > 0) {
            assertTrue(pass.saleClosed());
            assertGt(pass.totalMinted(), 40);
        }
        if (handler.ghostSeedEverSet()) {
            assertTrue(pass.seedSet());
            assertEq(pass.seed(), handler.ghostFirstSeed(), "seed rerolled");
            assertEq(pass.seedRequestId(), handler.ghostFirstSeedRequestId());
            assertEq(pass.totalMinted(), handler.ghostMintedAtSeed(), "mint after the seed");
            assertTrue(pass.saleClosed());
            assertEq(pass.seedRequestAvailableAt(), 0);
            assertEq(
                keccak256(abi.encode(pass.tierOf(41), pass.artworkIdOf(41))),
                handler.ghostOutcome41(),
                "outcome of 41 changed"
            );
            uint256 last = pass.totalMinted();
            assertEq(
                keccak256(abi.encode(pass.tierOf(last), pass.artworkIdOf(last))),
                handler.ghostOutcomeLast(),
                "outcome of last token changed"
            );
        } else {
            assertFalse(pass.seedSet());
            assertEq(pass.revealedCount(), 0);
        }
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SaleCloseIsFinal() public view {
        if (handler.ghostSaleEverClosed()) {
            assertTrue(pass.saleClosed(), "a closed sale reopened");
            assertEq(pass.currentPrice(), 0);
            assertEq(pass.remainingMysteryMints(), 0);
        }
        if (pass.totalMinted() == 500) assertTrue(pass.saleClosed());
    }

    /// forge-config: default.invariant.runs = 96
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RevealAccounting() public view {
        uint256 mystery = handler.ghostMysteryMints();
        uint256 revealed = pass.revealedCount();
        assertLe(revealed, mystery);
        assertEq(revealed, handler.ghostFinalizedTokens());
        assertEq(pass.pendingReveals(), mystery - revealed);
        assertLe(pass.mysteryGenesisRevealed(), 37);
        assertLe(revealed - pass.mysteryGenesisRevealed(), 423);
        assertEq(pass.remainingMysteryGenesis() + pass.remainingMysteryStandard(), 460 - revealed);
        assertFalse(handler.ghostDuplicateArtwork(), "an artwork was assigned twice or out of range");
        if (mystery > 0) {
            uint256 last = pass.totalMinted();
            uint8 status = uint8(pass.revealStatusOf(last));
            if (!pass.seedSet()) {
                assertEq(status, uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));
                assertEq(uint8(pass.tierOf(last)), uint8(BMCIlluminatiPass.Tier.Pending));
            } else if (revealed == mystery) {
                assertEq(status, uint8(BMCIlluminatiPass.RevealStatus.Revealed));
            } else {
                assertEq(status, uint8(BMCIlluminatiPass.RevealStatus.RandomnessStored));
                assertTrue(pass.tierOf(last) != BMCIlluminatiPass.Tier.Pending);
            }
        }
    }
}
