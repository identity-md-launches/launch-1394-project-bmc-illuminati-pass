// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {SubscriptionAPI} from "@chainlink/contracts/src/v0.8/vrf/dev/SubscriptionAPI.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";

/// @notice End-to-end check against Chainlink's own VRF v2.5 coordinator mock: subscription
///         creation, consumer registration, request ABI, fulfillment callback within the configured
///         callback gas limit, and the "unfunded subscription" failure and recovery path.
contract ChainlinkMockIntegrationTest is Test {
    MockBMC bmc;
    VRFCoordinatorV2_5Mock coordinator;
    BMCIlluminatiPass pass;
    uint256 subId;

    address owner = makeAddr("owner");
    address subOwner = makeAddr("subscriptionOwner");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1_760_000_000);
        bmc = new MockBMC();
        // base fee 0.1 LINK, gas price 1 gwei, 4e15 wei per LINK
        coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);

        vm.prank(subOwner);
        subId = coordinator.createSubscription();
        pass = new BMCIlluminatiPass(owner, address(bmc), address(coordinator), subId);
        vm.prank(subOwner);
        coordinator.addConsumer(subId, address(pass));

        for (uint256 i = 0; i < 40; i++) {
            address who = address(uint160(0x7000 + i));
            bmc.mint(who, 1_000_000e18);
            vm.startPrank(who);
            bmc.approve(address(pass), 1_000_000e18);
            pass.mintGenesis();
            vm.stopPrank();
        }
    }

    function _mystery() internal returns (uint256 id) {
        bmc.mint(alice, 350_000e18);
        vm.startPrank(alice);
        bmc.approve(address(pass), 350_000e18);
        id = pass.mintMystery();
        vm.stopPrank();
    }

    /// @dev nativePayment is true: the subscription must hold ETH, not LINK.
    function _fundNative(uint256 amount) internal {
        vm.deal(address(this), amount);
        coordinator.fundSubscriptionWithNative{value: amount}(subId);
    }

    function _closeSale() internal {
        vm.warp(block.timestamp + pass.SALE_IDLE_TIMEOUT());
        assertTrue(pass.saleClosed());
    }

    /// @dev The request is accepted while the subscription is unfunded; fulfilment fails until someone
    ///      funds it. Nothing was burned for the request, and the seed arrives once funded.
    function test_UnfundedSubscriptionKeepsSeedPendingUntilFunded() public {
        uint256 id = _mystery();
        _closeSale();
        uint256 req = pass.requestSeed();
        assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));
        vm.expectRevert(SubscriptionAPI.InsufficientBalance.selector);
        coordinator.fulfillRandomWords(req, address(pass));
        assertEq(uint8(pass.tierOf(id)), uint8(BMCIlluminatiPass.Tier.Pending));
        assertEq(pass.finalizeReveals(5), 0);
        // Anyone can fund; the pending request then completes.
        _fundNative(10 ether);
        coordinator.fulfillRandomWords(req, address(pass));
        assertTrue(pass.seedSet());
        assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.RandomnessStored));
        assertTrue(pass.tierOf(id) != BMCIlluminatiPass.Tier.Pending);
    }

    /// @dev Chainlink drops an underfunded request after 24 hours. After the contract's timeout anyone
    ///      requests again; the subscription is funded by then and the new request is fulfilled.
    function test_ExpiredRequestIsRecoveredByPermissionlessReRequest() public {
        uint256 id = _mystery();
        _closeSale();
        uint256 first = pass.requestSeed();
        vm.expectRevert(SubscriptionAPI.InsufficientBalance.selector);
        coordinator.fulfillRandomWords(first, address(pass));
        vm.warp(block.timestamp + pass.SEED_REQUEST_TIMEOUT());
        _fundNative(10 ether);
        vm.prank(alice);
        uint256 second = pass.requestSeed();
        assertTrue(second != first);
        coordinator.fulfillRandomWords(second, address(pass));
        assertTrue(pass.seedSet());
        assertEq(pass.seedRequestId(), second);
        assertTrue(pass.tierOf(id) != BMCIlluminatiPass.Tier.Pending);
        // A late delivery for the first request is ignored: first delivered word wins.
        coordinator.fulfillRandomWords(first, address(pass));
        assertEq(pass.seedRequestId(), second);
    }

    function test_NotAConsumerRevertsWithoutStateChange() public {
        _mystery();
        _closeSale();
        vm.prank(subOwner);
        coordinator.removeConsumer(subId, address(pass));
        _fundNative(10 ether);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionAPI.InvalidConsumer.selector, subId, address(pass)));
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 0);
        assertEq(pass.lastSeedRequestAt(), 0);
        // Once re-added, the request goes through: a configuration mistake only delays the seed.
        vm.prank(subOwner);
        coordinator.addConsumer(subId, address(pass));
        uint256 req = pass.requestSeed();
        coordinator.fulfillRandomWords(req, address(pass));
        assertTrue(pass.seedSet());
    }

    function test_RequestAndFulfilThroughChainlinkMockWithinCallbackGas() public {
        _fundNative(10 ether);
        uint256 id = _mystery();
        _closeSale();
        uint256 req = pass.requestSeed();
        assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));

        // The mock calls the consumer with exactly the request's callbackGasLimit (500,000).
        vm.expectEmit(true, false, false, false);
        emit BMCIlluminatiPass.SeedDelivered(req, 0);
        coordinator.fulfillRandomWords(req, address(pass));
        assertTrue(pass.seedSet());
        assertTrue(pass.tierOf(id) != BMCIlluminatiPass.Tier.Pending);
        assertEq(pass.finalizeReveals(10), 1);
        assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));

        // The mock refuses to fulfil the same request twice: no reroll path exists.
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        coordinator.fulfillRandomWords(req, address(pass));
    }

    function test_RecoveryPathRefusedWhenCoordinatorHasNoKeyRegistry() public {
        // Chainlink's mock has no `s_provingKeys`: the default lane is accepted (it cannot be checked)
        // and the recovery path, which must prove the lane exists, is refused.
        _mystery();
        _closeSale();
        bytes32 lane = pass.KEY_HASH();
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPass.KeyHashNotRegistered.selector, lane));
        pass.requestSeedWith(subId, lane);
        pass.requestSeed();
        assertEq(pass.seedRequestCount(), 1);
    }
}
