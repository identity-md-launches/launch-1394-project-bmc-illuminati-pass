// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

/// @notice Recovery from unavailable randomness: failed callbacks, expired requests, overlapping
///         requests with first-delivered-word-wins, lane and subscription fallback, and the absence
///         of any owner-controlled reroll or early seed disclosure.
contract VRFRecoveryTest is Test {
    MockBMC bmc;
    MockVRFCoordinator vrf;
    BMCIlluminatiPass pass;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address keeper = makeAddr("keeper");

    uint256 constant SUB_ID = 27852459484169864437638942739291618120641810244677084392617474192083559562985;
    bytes32 constant KEY_HASH = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;
    bytes32 constant OTHER_LANE = 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9;
    bytes32 constant BOGUS_LANE = 0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10c;

    uint256 timeout;

    function setUp() public {
        vm.warp(1_760_000_000);
        bmc = new MockBMC();
        vrf = new MockVRFCoordinator();
        vrf.setProvingKey(OTHER_LANE, true);
        pass = new BMCIlluminatiPass(owner, address(bmc), address(vrf), SUB_ID);
        timeout = pass.SEED_REQUEST_TIMEOUT();
        for (uint256 i = 0; i < 40; i++) {
            address who = address(uint160(0x1000 + i));
            bmc.mint(who, 1_000_000e18);
            vm.startPrank(who);
            bmc.approve(address(pass), 1_000_000e18);
            pass.mintGenesis();
            vm.stopPrank();
        }
        _mintMystery(alice);
        _mintMystery(bob);
        _mintMystery(alice);
        vm.warp(block.timestamp + pass.SALE_IDLE_TIMEOUT());
        assertTrue(pass.saleClosed());
    }

    function _mintMystery(address who) internal returns (uint256 id) {
        bmc.mint(who, 350_000e18);
        vm.startPrank(who);
        bmc.approve(address(pass), 350_000e18);
        id = pass.mintMystery();
        vm.stopPrank();
    }

    function _outcomes() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                pass.tierOf(41),
                pass.artworkIdOf(41),
                pass.tierOf(42),
                pass.artworkIdOf(42),
                pass.tierOf(43),
                pass.artworkIdOf(43)
            )
        );
    }

    // ------------------------------------------------------------------ failed callbacks

    function test_FailedCallbackLeavesSeedUnsetAndIsRecoverable() public {
        uint256 first = pass.requestSeed();
        // The coordinator calls back with too little gas: the callback fails, the request is consumed
        // (like the real coordinator records success=false) and no word is stored.
        assertFalse(vrf.fulfillWithGas(first, 11, 5_000));
        assertFalse(pass.seedSet());
        assertEq(uint8(pass.tierOf(41)), uint8(BMCIlluminatiPass.Tier.Pending));
        // Not yet: the timeout protects against spamming overlapping requests.
        vm.expectRevert(
            abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, pass.lastSeedRequestAt() + timeout)
        );
        pass.requestSeed();
        vm.warp(block.timestamp + timeout);
        vm.prank(keeper);
        uint256 second = pass.requestSeed();
        assertEq(pass.seedRequestCount(), 2);
        assertTrue(vrf.fulfill(second, 22));
        assertTrue(pass.seedSet());
        assertEq(pass.seed(), 22);
        assertEq(pass.seedRequestId(), second);
    }

    function test_CallbackRevertingOnUnknownRequestDoesNotTouchState() public {
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 5;
        vm.prank(address(vrf));
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.UnknownRequest.selector, req + 1));
        pass.rawFulfillRandomWords(req + 1, words);
        assertFalse(pass.seedSet());
        assertTrue(vrf.fulfill(req, 5));
        assertEq(pass.seed(), 5);
    }

    // ------------------------------------------------------------------ expired requests

    function test_ExpiredRequestReRequestedAfterTimeoutByAnyone() public {
        uint256 first = pass.requestSeed();
        uint256 retryAt = block.timestamp + timeout;
        assertEq(pass.seedRequestAvailableAt(), retryAt);
        vm.warp(retryAt - 1);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, retryAt));
        pass.requestSeed();
        vm.warp(retryAt);
        vm.prank(keeper);
        uint256 second = pass.requestSeed();
        assertTrue(second != first);
        assertEq(pass.lastSeedRequestAt(), retryAt);
        assertEq(pass.seedRequestAvailableAt(), retryAt + timeout);
        // Still nothing: a third request after another timeout, from yet another caller.
        vm.warp(retryAt + timeout);
        vm.prank(alice);
        uint256 third = pass.requestSeed();
        assertEq(pass.seedRequestCount(), 3);
        assertTrue(pass.isSeedRequest(first) && pass.isSeedRequest(second) && pass.isSeedRequest(third));
        assertTrue(vrf.fulfill(third, 333));
        assertEq(pass.seed(), 333);
        assertEq(pass.seedRequestAvailableAt(), 0);
    }

    // ------------------------------------------------------------------ first delivered word wins

    function test_OverlappingRequestsFirstDeliveredWordWins() public {
        uint256 first = pass.requestSeed();
        vm.warp(block.timestamp + timeout);
        uint256 second = pass.requestSeed();
        vm.warp(block.timestamp + timeout);
        uint256 third = pass.requestSeed();

        // The second request lands first: it is the seed, whatever arrives afterwards.
        assertTrue(vrf.fulfill(second, 2));
        assertEq(pass.seed(), 2);
        assertEq(pass.seedRequestId(), second);
        bytes32 outcomes = _outcomes();

        vm.expectEmit(true, false, false, true);
        emit BMCIlluminatiPass.SeedDeliveryIgnored(first, 1);
        assertTrue(vrf.fulfill(first, 1));
        assertTrue(vrf.fulfill(third, 3));
        assertTrue(vrf.redeliver(second, 4));
        assertEq(pass.seed(), 2);
        assertEq(pass.seedRequestId(), second);
        assertEq(_outcomes(), outcomes, "late or repeated deliveries change nothing");

        // Materialization uses the stored seed only.
        assertEq(pass.finalizeReveals(10), 3);
        assertEq(_outcomes(), outcomes);
    }

    function test_FirstDeliveredWordWinsRegardlessOfRequestOrder() public {
        uint256 first = pass.requestSeed();
        vm.warp(block.timestamp + timeout);
        uint256 second = pass.requestSeed();
        uint256 snap = vm.snapshotState();

        assertTrue(vrf.fulfill(first, 100));
        assertTrue(vrf.fulfill(second, 200));
        assertEq(pass.seed(), 100);

        vm.revertToState(snap);
        assertTrue(vrf.fulfill(second, 200));
        assertTrue(vrf.fulfill(first, 100));
        assertEq(pass.seed(), 200);
    }

    // ------------------------------------------------------------------ lane / subscription fallback

    function test_RecoveryFromAnotherLaneOrSubscription() public {
        uint256 first = pass.requestSeed();
        // No wait is needed: the timeout is per subscription, and this one has none pending.
        uint256 otherSub = 777;
        vm.prank(keeper);
        uint256 second = pass.requestSeedWith(otherSub, OTHER_LANE);
        (,,, bytes32 kh, uint256 sub,,) = vrf.requests(second);
        assertEq(kh, OTHER_LANE);
        assertEq(sub, otherSub);
        assertTrue(vrf.fulfill(second, 9));
        assertEq(pass.seed(), 9);
        assertTrue(vrf.fulfill(first, 8));
        assertEq(pass.seed(), 9);
    }

    // ------------------------------------------------------------------ foreign subscriptions cannot block

    /// @dev Independent review finding 2d181f82: a stranger's unfunded subscription used to arm the single
    ///      36-hour lock and keep `requestSeed()` out. The timeout is now per subscription.
    function test_UnfundedForeignSubscriptionNeverBlocksTheConfiguredSubscription() public {
        address griefer = makeAddr("griefer");
        uint256 grieferSub = 4242;
        for (uint256 cycle = 0; cycle < 3; cycle++) {
            // The griefer is first in the block in which a request becomes possible.
            vm.prank(griefer);
            uint256 foreign = pass.requestSeedWith(grieferSub, KEY_HASH);
            (,,,, uint256 sub,,) = vrf.requests(foreign);
            assertEq(sub, grieferSub);
            assertEq(pass.lastSeedRequestAtOf(grieferSub), block.timestamp);

            // Same block: the keeper's request from the configured subscription goes through.
            vm.prank(keeper);
            uint256 configured = pass.requestSeed();
            (,,,, sub,,) = vrf.requests(configured);
            assertEq(sub, SUB_ID, "request charged to the configured subscription");
            assertEq(pass.lastSeedRequestAt(), block.timestamp);
            assertTrue(pass.isSeedRequest(configured));

            // The foreign request is never fulfilled (no balance). The configured one would be, but
            // assume it fails too so the next cycle is reached.
            assertFalse(vrf.fulfillWithGas(configured, 1, 5_000));
            assertFalse(pass.seedSet());
            vm.warp(block.timestamp + timeout);
        }
        assertEq(pass.seedRequestCount(), 6, "three foreign and three configured requests, none blocked");
        // The configured subscription's own request is what finally delivers.
        vm.prank(keeper);
        uint256 last = pass.requestSeed();
        assertTrue(vrf.fulfill(last, 77));
        assertEq(pass.seed(), 77);
        assertEq(pass.seedRequestId(), last);
    }

    function test_TimeoutIsEnforcedPerSubscription() public {
        uint256 otherSub = 777;
        uint256 first = pass.requestSeed();
        // The configured subscription is rate-limited against itself ...
        vm.expectRevert(
            abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, block.timestamp + timeout)
        );
        pass.requestSeed();
        // ... a foreign subscription is not delayed by it, and is rate-limited against itself only.
        vm.prank(keeper);
        uint256 second = pass.requestSeedWith(otherSub, KEY_HASH);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, block.timestamp + timeout)
        );
        pass.requestSeedWith(otherSub, KEY_HASH);
        vm.prank(alice);
        uint256 third = pass.requestSeedWith(999, OTHER_LANE);
        assertEq(pass.seedRequestCount(), 3);
        assertEq(pass.seedRequestAvailableAt(), block.timestamp + timeout, "view reports the configured subscription");
        // A foreign request can still be the one that delivers: first delivered word wins.
        assertTrue(vrf.fulfill(second, 2));
        assertEq(pass.seed(), 2);
        assertTrue(vrf.fulfill(first, 1));
        assertTrue(vrf.fulfill(third, 3));
        assertEq(pass.seed(), 2);
        // Once set, every path is closed for every subscription.
        vm.warp(block.timestamp + timeout);
        vm.expectRevert(BMCIlluminatiPass.SeedAlreadyDelivered.selector);
        pass.requestSeedWith(otherSub, KEY_HASH);
    }

    function test_StrangerCannotMoveTheConfiguredSubscriptionToAnotherLane() public {
        // While the default lane is registered, the configured subscription only requests on it.
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.DefaultLaneStillRegistered.selector, KEY_HASH));
        pass.requestSeedWith(SUB_ID, OTHER_LANE);
        assertEq(vrf.requestCount(), 0);
        assertEq(pass.lastSeedRequestAt(), 0);
        // `requestSeedWith` on the configured subscription and lane is the same request as `requestSeed`.
        vm.prank(keeper);
        uint256 req = pass.requestSeedWith(SUB_ID, KEY_HASH);
        (,,, bytes32 kh, uint256 sub,,) = vrf.requests(req);
        assertEq(kh, KEY_HASH);
        assertEq(sub, SUB_ID);
        vm.expectRevert(
            abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, block.timestamp + timeout)
        );
        pass.requestSeed();
        // Another lane at a stranger's own cost is always fine.
        vm.prank(keeper);
        pass.requestSeedWith(777, OTHER_LANE);
        // Once the coordinator retires the default lane, the configured subscription may use another.
        vm.warp(block.timestamp + timeout);
        vrf.setProvingKey(KEY_HASH, false);
        vm.prank(keeper);
        uint256 moved = pass.requestSeedWith(SUB_ID, OTHER_LANE);
        (,,, kh, sub,,) = vrf.requests(moved);
        assertEq(kh, OTHER_LANE);
        assertEq(sub, SUB_ID);
    }

    function test_UnregisteredLaneIsRefusedBeforeAnyRequest() public {
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, BOGUS_LANE));
        pass.requestSeedWith(SUB_ID, BOGUS_LANE);
        assertEq(vrf.requestCount(), 0);
        assertEq(pass.seedRequestCount(), 0);
        assertEq(pass.lastSeedRequestAt(), 0, "a refused request does not start the timeout");
    }

    function test_DefaultLaneIsCheckedAgainstTheRegistryWhenAvailable() public {
        vrf.setProvingKey(KEY_HASH, false); // lane retired on the coordinator
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, KEY_HASH));
        pass.requestSeed();
        // The permissionless fallback to another registered lane still works.
        uint256 req = pass.requestSeedWith(SUB_ID, OTHER_LANE);
        assertTrue(vrf.fulfill(req, 1));
        assertTrue(pass.seedSet());
    }

    function test_DefaultLaneAcceptedWhenRegistryUnavailable() public {
        vrf.setHideRegistry(true);
        uint256 req = pass.requestSeed();
        (,,, bytes32 kh,,,) = vrf.requests(req);
        assertEq(kh, KEY_HASH);
        vm.warp(block.timestamp + timeout);
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, OTHER_LANE));
        pass.requestSeedWith(SUB_ID, OTHER_LANE);
    }

    function test_CoordinatorRejectionLeavesNoTrace() public {
        vrf.setRejectRequests(true);
        vm.expectRevert(bytes("mock: request rejected"));
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 0);
        assertEq(pass.lastSeedRequestAt(), 0);
        vrf.setRejectRequests(false);
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 1);
    }

    // ------------------------------------------------------------------ no owner reroll, no early seed

    function test_OwnerCannotRerollRedirectOrPreview() public {
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.startPrank(owner);
        vm.expectRevert(BMCIlluminatiPass.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(req, words);
        vm.expectRevert(
            abi.encodeWithSelector(BMCIlluminatiPass.SeedRequestPending.selector, pass.lastSeedRequestAt() + timeout)
        );
        pass.requestSeed();
        vm.stopPrank();
        assertTrue(vrf.fulfill(req, 1));
        bytes32 outcomes = _outcomes();
        // After delivery the owner has no path to a new request or a different coordinator.
        vm.startPrank(owner);
        vm.expectRevert(BMCIlluminatiPass.SeedAlreadyDelivered.selector);
        pass.requestSeed();
        vm.expectRevert(BMCIlluminatiPass.SeedAlreadyDelivered.selector);
        pass.requestSeedWith(1, OTHER_LANE);
        pass.renounceOwnership();
        vm.stopPrank();
        assertEq(pass.owner(), address(0));
        // Renouncing changes nothing operationally: anyone can still materialize.
        assertEq(pass.finalizeReveals(10), 3);
        assertEq(_outcomes(), outcomes);
    }

    function test_SeedCannotBeRequestedBeforeSaleCloses() public {
        // Fresh contract with an open sale: no path requests randomness while mints are possible.
        BMCIlluminatiPass p = new BMCIlluminatiPass(owner, address(bmc), address(vrf), SUB_ID);
        for (uint256 i = 0; i < 40; i++) {
            address who = address(uint160(0x2000 + i));
            bmc.mint(who, 1_000_000e18);
            vm.startPrank(who);
            bmc.approve(address(p), 1_000_000e18);
            p.mintGenesis();
            vm.stopPrank();
        }
        bmc.mint(alice, 350_000e18);
        vm.startPrank(alice);
        bmc.approve(address(p), 350_000e18);
        p.mintMystery();
        vm.stopPrank();
        uint256 before = vrf.requestCount();
        vm.prank(owner);
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        p.requestSeed();
        vm.prank(owner);
        vm.expectRevert(BMCIlluminatiPass.SaleNotClosed.selector);
        p.requestSeedWith(SUB_ID, OTHER_LANE);
        assertEq(vrf.requestCount(), before);
        assertFalse(p.seedSet());
    }
}
