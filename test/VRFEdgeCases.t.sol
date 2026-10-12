// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MysteryDraw} from "../src/MysteryDraw.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

/// @dev Coordinator that returns whatever request id the test programs (0, or the same id twice) and
///      exposes a registry. Models a misbehaving or upgraded coordinator.
contract ProgrammableIdCoordinator {
    uint256 public nextId;
    bool public repeat;
    bytes public lastExtraArgs;
    uint256 public calls;

    function setNextId(uint256 id, bool repeatIds) external {
        nextId = id;
        repeat = repeatIds;
    }

    function s_provingKeys(bytes32) external pure returns (bool exists, uint64 maxGas) {
        return (true, 500 gwei);
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 id) {
        calls++;
        lastExtraArgs = req.extraArgs;
        id = nextId;
        if (!repeat) nextId++;
    }

    function deliver(address consumer, uint256 requestId, uint256[] memory words, uint256 gas)
        external
        returns (bool ok)
    {
        (ok,) = consumer.call{gas: gas}(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, words)
        );
    }
}

/// @dev Coordinator whose `s_provingKeys` returns a single word (a future ABI): too short to decode.
contract ShortRegistryCoordinator {
    uint256 public nextId = 1;

    function s_provingKeys(bytes32) external pure returns (bool exists) {
        return false; // would mean "unregistered" if the ABI matched
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256 id) {
        id = nextId++;
    }
}

/// @dev Receiver that refuses every token.
contract RejectingReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        revert("no thanks");
    }
}

/// @dev Receiver that tries to request the seed or finalize from inside the mint callback.
contract SeedGrabber is IERC721Receiver {
    BMCIlluminatiPass public pass;
    bytes public lastRevert;
    uint256 public finalized;

    constructor(BMCIlluminatiPass p) {
        pass = p;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        try pass.requestSeed() {}
        catch (bytes memory r) {
            lastRevert = r;
        }
        finalized = pass.finalizeReveals(10);
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @notice Inputs the implementation did not necessarily consider: a coordinator returning request
///         id 0 or a repeated id, a registry with a different ABI, multi-word deliveries, extreme
///         seeds, exact timeout boundaries (fuzzed), reverting receivers, requests from inside the
///         mint callback, a sale that closes with no mystery mint, batch-split independence of the
///         materialization, the extraArgs encoding and the gas envelope of the callback and of
///         `finalizeReveals`.
contract VRFEdgeCasesTest is Test {
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
    bytes32 constant OTHER_LANE = 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9;

    function setUp() public {
        vm.warp(1_760_000_000);
        bmc = new MockBMC();
        vrf = new MockVRFCoordinator();
        vrf.setProvingKey(OTHER_LANE, true);
        pass = new BMCIlluminatiPass(owner, address(bmc), address(vrf), SUB_ID);
    }

    // ------------------------------------------------------------------ helpers

    function _mintGenesisOn(BMCIlluminatiPass p, address who) internal returns (uint256 id) {
        bmc.mint(who, GENESIS_PRICE);
        vm.startPrank(who);
        bmc.approve(address(p), GENESIS_PRICE);
        id = p.mintGenesis();
        vm.stopPrank();
    }

    function _mintMysteryOn(BMCIlluminatiPass p, address who) internal returns (uint256 id) {
        bmc.mint(who, MYSTERY_PRICE);
        vm.startPrank(who);
        bmc.approve(address(p), MYSTERY_PRICE);
        id = p.mintMystery();
        vm.stopPrank();
    }

    function _finishPhase1On(BMCIlluminatiPass p) internal {
        for (uint256 i = 0; i < 40; i++) {
            _mintGenesisOn(p, address(uint160(0x1000 + i)));
        }
    }

    function _finishPhase1() internal {
        _finishPhase1On(pass);
    }

    function _closeByIdle(BMCIlluminatiPass p) internal {
        vm.warp(block.timestamp + p.SALE_IDLE_TIMEOUT());
        assertTrue(p.saleClosed());
    }

    function _words(uint256 w) internal pure returns (uint256[] memory words) {
        words = new uint256[](1);
        words[0] = w;
    }

    // ------------------------------------------------------------------ coordinator misbehaviour

    function test_RequestIdZeroFromCoordinatorIsRefusedWithoutStartingTheTimeout() public {
        ProgrammableIdCoordinator c = new ProgrammableIdCoordinator();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(c), SUB_ID);
        _finishPhase1On(p);
        _mintMysteryOn(p, alice);
        _closeByIdle(p);
        c.setNextId(0, true);
        vm.expectRevert(bytes("duplicate request id"));
        p.requestSeed();
        assertEq(p.seedRequestCount(), 0);
        assertEq(p.lastSeedRequestAt(), 0, "a refused request must not block the next attempt");
        assertFalse(p.isSeedRequest(0));
        // Once the coordinator behaves, the request goes through immediately.
        c.setNextId(5, false);
        assertEq(p.requestSeed(), 5);
        assertTrue(p.isSeedRequest(5));
    }

    function test_RepeatedRequestIdFromCoordinatorIsRefused() public {
        ProgrammableIdCoordinator c = new ProgrammableIdCoordinator();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(c), SUB_ID);
        _finishPhase1On(p);
        _mintMysteryOn(p, alice);
        _closeByIdle(p);
        c.setNextId(42, true);
        assertEq(p.requestSeed(), 42);
        vm.warp(block.timestamp + p.SEED_REQUEST_TIMEOUT());
        vm.expectRevert(bytes("duplicate request id"));
        p.requestSeed();
        assertEq(p.seedRequestCount(), 1);
        // The original request is still a valid one and can deliver the seed.
        assertTrue(c.deliver(address(p), 42, _words(7), 500_000));
        assertEq(p.seed(), 7);
    }

    function test_ExtraArgsCarryTheV1TagAndNativePayment() public {
        ProgrammableIdCoordinator c = new ProgrammableIdCoordinator();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(c), SUB_ID);
        _finishPhase1On(p);
        _mintMysteryOn(p, alice);
        _closeByIdle(p);
        c.setNextId(1, false);
        p.requestSeed();
        bytes memory extra = c.lastExtraArgs();
        assertEq(extra.length, 36, "tag + one abi word");
        assertEq(bytes4(extra), VRFV2PlusClient.EXTRA_ARGS_V1_TAG);
        bytes memory body = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            body[i] = extra[i + 4];
        }
        VRFV2PlusClient.ExtraArgsV1 memory ea = abi.decode(body, (VRFV2PlusClient.ExtraArgsV1));
        assertTrue(ea.nativePayment, "subscription is paid in ETH");
    }

    function test_RegistryWithDifferentAbiIsTreatedAsAbsent() public {
        // A 32-byte answer is too short for (bool, uint64): the default lane is accepted unchecked
        // and the recovery path, which must prove its lane, is refused. Nothing decodes garbage.
        ShortRegistryCoordinator c = new ShortRegistryCoordinator();
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(c), SUB_ID);
        _finishPhase1On(p);
        _mintMysteryOn(p, alice);
        _closeByIdle(p);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, KEY_HASH));
        p.requestSeedWith(SUB_ID, KEY_HASH);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, OTHER_LANE));
        p.requestSeedWith(SUB_ID, OTHER_LANE);
        assertEq(p.requestSeed(), 1);
    }

    function test_CoordinatorWithoutCodeCannotBeRequestedButMintsStillWork() public {
        // Misconfigured coordinator address: mints are unaffected, only the seed request reverts.
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(0xC0FFEE), SUB_ID);
        _finishPhase1On(p);
        _mintMysteryOn(p, alice);
        _closeByIdle(p);
        vm.expectRevert();
        p.requestSeed();
        assertEq(p.seedRequestCount(), 0);
        assertEq(p.totalMinted(), 41);
    }

    // ------------------------------------------------------------------ deliveries

    function test_MultiWordDeliveryUsesOnlyTheFirstWord() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](3);
        words[0] = 111;
        words[1] = 222;
        words[2] = 333;
        vm.prank(address(vrf));
        pass.rawFulfillRandomWords(req, words);
        assertEq(pass.seed(), 111);
        (bool g, uint16 art) = MysteryDraw.decode(MysteryDraw.slotAt(111, 0));
        assertEq(pass.artworkIdOf(41), art);
        assertEq(pass.tierOf(41) == BMCIlluminatiPass.Tier.Genesis, g);
    }

    function test_SeedZeroAndSeedMaxAreValidSeeds() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _mintMysteryOn(pass, bob);
        _closeByIdle(pass);
        uint256 snap = vm.snapshotState();

        uint256 req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, 0));
        assertTrue(pass.seedSet(), "a zero word still counts as delivered");
        assertEq(pass.seed(), 0);
        assertTrue(pass.tierOf(41) != BMCIlluminatiPass.Tier.Pending);
        // A later delivery cannot replace a zero seed either.
        assertTrue(vrf.redeliver(req, 99));
        assertEq(pass.seed(), 0);
        assertEq(pass.finalizeReveals(5), 2);

        vm.revertToState(snap);
        req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, type(uint256).max));
        assertEq(pass.seed(), type(uint256).max);
        assertEq(pass.finalizeReveals(5), 2);
        uint16 a = pass.artworkIdOf(41);
        uint16 b = pass.artworkIdOf(42);
        assertTrue(a != b || pass.tierOf(41) != pass.tierOf(42), "two draws never share an outcome");
    }

    function test_CallbackFailingForWantOfGasIsRetriableWithoutStateChange() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        uint256 req = pass.requestSeed();
        for (uint256 gas = 1_000; gas <= 30_000; gas += 7_000) {
            uint256 snap = vm.snapshotState();
            bool ok = vrf.fulfillWithGas(req, 5, gas);
            if (!ok) {
                assertFalse(pass.seedSet());
                assertTrue(pass.isSeedRequest(req), "request stays valid after a failed callback");
                assertEq(uint8(pass.revealStatusOf(41)), uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));
            } else {
                assertEq(pass.seed(), 5);
            }
            vm.revertToState(snap);
        }
    }

    function test_SeedIsNotDisclosedBeforeDelivery() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        pass.requestSeed();
        // Between request and delivery nothing reveals anything: no outcome, no artwork, no seed.
        assertFalse(pass.seedSet());
        assertEq(pass.seed(), 0);
        assertEq(pass.seedRequestId(), 0);
        assertEq(uint8(pass.tierOf(41)), uint8(BMCIlluminatiPass.Tier.Pending));
        assertEq(pass.artworkIdOf(41), 0);
        assertEq(pass.finalizeReveals(1), 0);
        assertEq(pass.revealedCount(), 0);
    }

    // ------------------------------------------------------------------ timeouts (fuzzed boundaries)

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_ReRequestExactlyAtTimeoutBoundary(uint64 lateness) public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        uint256 first = pass.requestSeed();
        uint256 retryAt = block.timestamp + pass.SEED_REQUEST_TIMEOUT();
        uint256 t = bound(uint256(lateness), 0, 2 * pass.SEED_REQUEST_TIMEOUT());
        vm.warp(block.timestamp + t);
        if (block.timestamp < retryAt) {
            vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, retryAt));
            pass.requestSeed();
            assertEq(pass.seedRequestCount(), 1);
        } else {
            uint256 second = pass.requestSeed();
            assertTrue(second != first);
            assertEq(pass.seedRequestCount(), 2);
            assertEq(pass.lastSeedRequestAt(), block.timestamp);
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_SaleCloseExactlyAtIdleBoundary(uint64 elapsed, uint8 mysteryMints) public {
        _finishPhase1();
        uint256 n = bound(uint256(mysteryMints), 0, 5);
        for (uint256 i = 0; i < n; i++) {
            vm.warp(block.timestamp + 1 days);
            _mintMysteryOn(pass, alice);
        }
        uint256 lastMint = pass.lastMintAt();
        uint256 t = bound(uint256(elapsed), 0, 2 * pass.SALE_IDLE_TIMEOUT());
        vm.warp(lastMint + t);
        bool closed = t >= pass.SALE_IDLE_TIMEOUT();
        assertEq(pass.saleClosed(), closed);
        assertEq(pass.currentPrice(), closed ? 0 : MYSTERY_PRICE);
        assertEq(pass.remainingMysteryMints(), closed ? 0 : 460 - n);
        bmc.mint(bob, MYSTERY_PRICE);
        vm.startPrank(bob);
        bmc.approve(address(pass), MYSTERY_PRICE);
        if (closed) vm.expectRevert(BMCIlluminatiPass.SaleIsClosed.selector);
        pass.mintMystery();
        vm.stopPrank();
        if (closed) {
            assertEq(bmc.balanceOf(bob), MYSTERY_PRICE, "nothing burned once closed");
            if (n == 0) {
                vm.expectRevert(BMCIlluminatiPass.NothingToReveal.selector);
            }
            pass.requestSeed();
        } else {
            vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
            pass.requestSeed();
        }
    }

    function test_SaleClosingWithNoMysteryMintIsTerminal() public {
        // Documented rule: 30 idle days right after the Genesis phase close the sale at 40 tokens for
        // good. No seed is ever needed and no mint can reopen it.
        _finishPhase1();
        _closeByIdle(pass);
        assertEq(pass.totalMinted(), 40);
        assertEq(pass.remainingSupply(), 460, "460 ids are never minted");
        assertEq(pass.remainingMysteryMints(), 0);
        assertEq(pass.pendingReveals(), 0);
        vm.expectRevert(BMCIlluminatiPass.NothingToReveal.selector);
        pass.requestSeed();
        vm.expectRevert(BMCIlluminatiPass.NothingToReveal.selector);
        pass.requestSeedWith(SUB_ID, OTHER_LANE);
        assertEq(pass.seedRequestAvailableAt(), pass.lastMintAt() + 30 days, "reported even though nothing to reveal");
        bmc.mint(alice, MYSTERY_PRICE);
        vm.startPrank(alice);
        bmc.approve(address(pass), MYSTERY_PRICE);
        vm.expectRevert(BMCIlluminatiPass.SaleIsClosed.selector);
        pass.mintMystery();
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        assertTrue(pass.saleClosed());
    }

    // ------------------------------------------------------------------ receivers and reentrancy

    function test_RejectingReceiverBurnsNothingAndMintsNothing() public {
        RejectingReceiver r = new RejectingReceiver();
        bmc.mint(address(r), GENESIS_PRICE);
        vm.prank(address(r));
        bmc.approve(address(pass), GENESIS_PRICE);
        vm.prank(address(r));
        vm.expectRevert(bytes("no thanks"));
        pass.mintGenesis();
        assertEq(pass.totalMinted(), 0);
        assertEq(pass.totalBurned(), 0);
        assertEq(bmc.balanceOf(address(r)), GENESIS_PRICE);
        assertEq(bmc.totalSupply(), GENESIS_PRICE);
    }

    function test_MintCallbackCannotRequestSeedOrFinalize() public {
        _finishPhase1();
        SeedGrabber g = new SeedGrabber(pass);
        // Make the sale "closed by sold-out" impossible here; the grabber mints the 41st token while
        // the sale is open, then tries to request from inside the receiver hook.
        bmc.mint(address(g), MYSTERY_PRICE);
        vm.prank(address(g));
        bmc.approve(address(pass), MYSTERY_PRICE);
        vm.prank(address(g));
        uint256 id = pass.mintMystery();
        assertEq(id, 41);
        assertEq(g.finalized(), 0);
        assertEq(pass.seedRequestCount(), 0);
        assertEq(vrf.requestCount(), 0);
        assertGt(g.lastRevert().length, 0, "the inner request reverted");
    }

    function test_FinalMintOfTheSaleCannotRequestInTheSameCall() public {
        // 500th mint from a receiver that requests the seed in its hook: the shared reentrancy guard
        // refuses it even though the sale is closed by then.
        _finishPhase1();
        for (uint256 i = 0; i < 459; i++) {
            _mintMysteryOn(pass, address(uint160(0x5000 + (i % 50))));
        }
        SeedGrabber g = new SeedGrabber(pass);
        bmc.mint(address(g), MYSTERY_PRICE);
        vm.prank(address(g));
        bmc.approve(address(pass), MYSTERY_PRICE);
        vm.prank(address(g));
        assertEq(pass.mintMystery(), 500);
        assertTrue(pass.saleClosed());
        assertEq(pass.seedRequestCount(), 0);
        assertEq(vrf.requestCount(), 0);
        // Reentrancy guard error from OpenZeppelin.
        assertEq(bytes4(g.lastRevert()), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        // After the mint transaction anyone can request.
        vm.prank(bob);
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 1);
    }

    // ------------------------------------------------------------------ ownership

    function test_NewOwnerHasNoPowerEither() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        vm.prank(owner);
        pass.transferOwnership(bob);
        assertEq(pass.owner(), bob);
        uint256 req = pass.requestSeed();
        vm.startPrank(bob);
        vm.expectRevert(BMCIlluminatiPass.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(req, _words(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                BMCIlluminatiPass.SeedRequestPending.selector, pass.lastSeedRequestAt() + pass.SEED_REQUEST_TIMEOUT()
            )
        );
        pass.requestSeedWith(1, OTHER_LANE);
        vm.stopPrank();
        assertTrue(vrf.fulfill(req, 1));
        assertEq(pass.seed(), 1);
    }

    // ------------------------------------------------------------------ materialization

    /// forge-config: default.fuzz.runs = 32
    function testFuzz_MaterializationIsIndependentOfBatchSplit(uint256 seedWord, uint8 batchA, uint8 batchB) public {
        _finishPhase1();
        uint256 n = 60;
        for (uint256 i = 0; i < n; i++) {
            _mintMysteryOn(pass, alice);
        }
        _closeByIdle(pass);
        uint256 req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, seedWord));
        uint256 a = bound(uint256(batchA), 0, n + 5);
        uint256 b = bound(uint256(batchB), 0, n + 5);
        uint256 done = pass.finalizeReveals(a);
        assertEq(done, a > n ? n : a);
        done += pass.finalizeReveals(b);
        done += pass.finalizeReveals(type(uint256).max);
        assertEq(done, n);
        assertEq(pass.revealedCount(), n);
        uint256 genesis;
        for (uint256 i = 0; i < n; i++) {
            (bool g, uint16 art) = MysteryDraw.decode(MysteryDraw.slotAt(seedWord, i));
            assertEq(pass.artworkIdOf(41 + i), art, "stored outcome differs from the memory draw");
            assertEq(pass.tierOf(41 + i) == BMCIlluminatiPass.Tier.Genesis, g);
            if (g) genesis++;
        }
        assertEq(pass.mysteryGenesisRevealed(), genesis);
        assertEq(pass.remainingMysteryGenesis(), 37 - genesis);
        assertEq(pass.remainingMysteryStandard(), 423 - (n - genesis));
    }

    function test_FinalizeZeroIsANoOpAndOverflowingBatchStopsAtTheEnd() public {
        _finishPhase1();
        _mintMysteryOn(pass, alice);
        _closeByIdle(pass);
        uint256 req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, 1));
        assertEq(pass.finalizeReveals(0), 0);
        assertEq(pass.revealedCount(), 0);
        assertEq(pass.finalizeReveals(type(uint256).max), 1);
        assertEq(pass.finalizeReveals(type(uint256).max), 0);
        assertEq(pass.revealedCount(), 1);
    }

    // ------------------------------------------------------------------ gas envelope

    function test_CallbackGasStaysUnderAFifthOfTheLimit() public {
        _finishPhase1();
        for (uint256 i = 0; i < 460; i++) {
            _mintMysteryOn(pass, address(uint160(0x5000 + (i % 50))));
        }
        uint256 req = pass.requestSeed();
        uint256[] memory words = _words(uint256(keccak256("gas")));
        vm.prank(address(vrf));
        uint256 before = gasleft();
        pass.rawFulfillRandomWords(req, words);
        uint256 used = before - gasleft();
        // Measured from the caller: ~76k including the cold account and storage accesses.
        assertLt(used, 100_000, "callback cost independent of supply and far below 500,000");
        // The ignored path is cheaper still.
        vm.prank(address(vrf));
        before = gasleft();
        pass.rawFulfillRandomWords(req, words);
        assertLt(before - gasleft(), 40_000);
    }

    function test_FinalizeAllInOneTransactionExceedsThirtyMillionGas() public {
        // Operational note for the keeper: 460 steps in one call is above 30M gas, so batches are
        // required. Each step is bounded, so any batch size <= 100 fits comfortably.
        _finishPhase1();
        for (uint256 i = 0; i < 460; i++) {
            _mintMysteryOn(pass, address(uint160(0x5000 + (i % 50))));
        }
        uint256 req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, 1));
        uint256 before = gasleft();
        assertEq(pass.finalizeReveals(100), 100);
        uint256 hundred = before - gasleft();
        assertLt(hundred, 8_000_000, "a 100-token batch fits in a quarter of a block");
        before = gasleft();
        assertEq(pass.finalizeReveals(360), 360);
        uint256 rest = before - gasleft();
        assertLt(rest, 30_000_000, "the remaining 360 fit in one block");
        assertEq(pass.revealedCount(), 460);
    }

    function test_ViewsOfTheLastTokenBeforeMaterializationFitAnEthCall() public {
        _finishPhase1();
        for (uint256 i = 0; i < 460; i++) {
            _mintMysteryOn(pass, address(uint160(0x5000 + (i % 50))));
        }
        uint256 req = pass.requestSeed();
        assertTrue(vrf.fulfill(req, 1));
        uint256 before = gasleft();
        pass.tierOf(500);
        assertLt(before - gasleft(), 1_000_000);
        before = gasleft();
        pass.tokenURI(500);
        assertLt(before - gasleft(), 1_500_000);
    }

    // ------------------------------------------------------------------ configuration

    function test_ConfigurationFitsTheMainnetCoordinatorLimits() public view {
        // Mainnet VRF v2.5 coordinator: min confirmations 3, max callback gas 2,500,000.
        assertGe(pass.REQUEST_CONFIRMATIONS(), 3);
        assertLe(pass.CALLBACK_GAS_LIMIT(), 2_500_000);
        assertEq(pass.CALLBACK_GAS_LIMIT(), 500_000);
        assertTrue(pass.NATIVE_PAYMENT());
        assertEq(pass.SUBSCRIPTION_ID(), SUB_ID);
        assertEq(pass.KEY_HASH(), KEY_HASH);
        assertEq(address(pass.VRF_COORDINATOR()), address(vrf));
    }
}
