// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MysteryDraw} from "../src/MysteryDraw.sol";

/// @notice Properties of the seed-driven draw: for every seed the 460 steps are a permutation of the
///         pool (exactly 37 Genesis and 423 Standard, every artwork once), every mint position has the
///         same Genesis odds across seeds, and the memory draw equals the project's prototype draw.
contract RarityFairnessTest is Test {
    uint256 constant POOL = 460;
    uint256 constant GENESIS = 37;

    /// @dev The requester's `BMCPassVRFPrototype.draw`, verbatim semantics (eager pool).
    function _prototypeDraw(uint256 seed) internal pure returns (uint16[] memory outcomes) {
        outcomes = new uint16[](POOL);
        uint16[460] memory pool;
        for (uint256 i; i < POOL; ++i) {
            pool[i] = uint16(i);
        }
        for (uint256 i; i < POOL; ++i) {
            uint256 remaining = POOL - i;
            uint256 randomIndex = uint256(keccak256(abi.encode(seed, i))) % remaining;
            outcomes[i] = pool[randomIndex];
            pool[randomIndex] = pool[remaining - 1];
        }
    }

    function _checkPermutation(uint256 seed) internal pure returns (uint16[] memory outcomes) {
        outcomes = _prototypeDraw(seed);
        bool[460] memory seen;
        uint256 genesis;
        for (uint256 i; i < POOL; ++i) {
            uint256 slot = outcomes[i];
            assertLt(slot, POOL);
            assertFalse(seen[slot], "slot drawn twice");
            seen[slot] = true;
            (bool g, uint16 art) = MysteryDraw.decode(slot);
            if (g) {
                genesis++;
                assertTrue(art >= 41 && art <= 77);
            } else {
                assertTrue(art >= 1 && art <= 423);
            }
        }
        assertEq(genesis, GENESIS, "exactly 37 mystery Genesis per seed");
    }

    function test_DrawIsAPermutationForFixedSeeds() public pure {
        _checkPermutation(0);
        _checkPermutation(type(uint256).max);
        _checkPermutation(uint256(keccak256("bmc")));
    }

    function testFuzz_DrawIsAPermutation(uint256 seed) public pure {
        _checkPermutation(seed);
    }

    function testFuzz_LibraryMatchesPrototypeAtEveryStep(uint256 seed) public pure {
        uint16[] memory expected = _prototypeDraw(seed);
        // Sample every step cheaply plus the full range for a few indices.
        for (uint256 i; i < POOL; i += 23) {
            assertEq(MysteryDraw.slotAt(seed, i), expected[i], "library step differs from prototype");
        }
        assertEq(MysteryDraw.slotAt(seed, 0), expected[0]);
        assertEq(MysteryDraw.slotAt(seed, POOL - 1), expected[POOL - 1]);
    }

    function test_LibraryMatchesPrototypeForAllSteps() public pure {
        uint256 seed = uint256(keccak256("all steps"));
        uint16[] memory expected = _prototypeDraw(seed);
        for (uint256 i; i < POOL; ++i) {
            assertEq(MysteryDraw.slotAt(seed, i), expected[i]);
        }
    }

    /// @dev Over many seeds, each mint position (first, middle, last) is Genesis about 37/460 of the
    ///      time. Positions are grouped in 10 bands of 46 so each band has 46 * SEEDS samples; the
    ///      expected band rate is 8.04%, and a band outside 6.5%..9.6% would be a > 6 sigma event.
    function test_EveryMintPositionHasTheSameGenesisOdds() public pure {
        uint256 SEEDS = 200;
        uint256[10] memory bandHits;
        for (uint256 s; s < SEEDS; ++s) {
            uint16[] memory outcomes = _prototypeDraw(uint256(keccak256(abi.encode("fairness", s))));
            for (uint256 i; i < POOL; ++i) {
                if (outcomes[i] < GENESIS) bandHits[i / 46]++;
            }
        }
        uint256 samplesPerBand = 46 * SEEDS; // 9,200
        for (uint256 b; b < 10; ++b) {
            uint256 rateBps = bandHits[b] * 10_000 / samplesPerBand; // expected 804 bps
            assertGt(rateBps, 650, "band below expected Genesis rate");
            assertLt(rateBps, 960, "band above expected Genesis rate");
        }
    }

    /// @dev Mint order carries no information: the last position is Genesis as often as the first.
    ///      Step 0 needs no pool, so it is sampled over 2,000 seeds; the last step needs a full draw
    ///      and is sampled over 150 seeds (memory bound of a single test frame).
    function test_FirstAndLastPositionsAreNotPrivileged() public pure {
        uint256 firstHits;
        for (uint256 s; s < 2000; ++s) {
            if (MysteryDraw.pick(uint256(keccak256(abi.encode("first", s))), 0) < GENESIS) firstHits++;
        }
        // Expected 161 of 2,000 (sd ~12.2); accept 100..225.
        assertTrue(firstHits >= 100 && firstHits <= 225, "first position odds off");

        uint256 lastHits;
        for (uint256 s; s < 150; ++s) {
            uint16[] memory outcomes = _prototypeDraw(uint256(keccak256(abi.encode("last", s))));
            if (outcomes[POOL - 1] < GENESIS) lastHits++;
        }
        // Expected 12 of 150 (sd ~3.3); accept 2..26.
        assertTrue(lastHits >= 2 && lastHits <= 26, "last position odds off");
    }
}
