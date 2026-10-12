// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title MysteryDraw
/// @notice Pure, seed-driven draw without replacement over the 460 mystery outcomes.
/// @dev Slot values 0..36 are the 37 mystery Genesis outcomes (genesis-41 .. genesis-77); 37..459 are
///      the 423 Standard outcomes (standard-1 .. standard-423). The draw is the Fisher-Yates variant of
///      the project's `BMCPassVRFPrototype.draw`: at step `i` the index `keccak256(seed, i) % (460 - i)`
///      is taken from the pool and the last live slot moves into the hole. Step `i` is the outcome of
///      mystery token `41 + i`, so an outcome depends only on the seed and on steps before it: it is the
///      same whether it is computed in memory, incrementally in storage, or by an off-chain observer.
///      Every function is internal so no link placeholder is left in the caller's bytecode.
library MysteryDraw {
    uint256 internal constant POOL = 460;
    uint256 internal constant GENESIS_SLOTS = 37;

    /// @notice Uniform index for step `i` of the draw under `seed`.
    function pick(uint256 seed, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, i))) % (POOL - i);
    }

    /// @notice Slot drawn at step `index` (0-based) under `seed`, computed in memory.
    function slotAt(uint256 seed, uint256 index) internal pure returns (uint256 slot) {
        require(index < POOL, "MysteryDraw: index");
        // pool[j] == 0 means "slot j still holds value j"; otherwise it holds value + 1.
        uint256[POOL] memory pool;
        for (uint256 i; i <= index; ++i) {
            uint256 r = pick(seed, i);
            uint256 last = POOL - 1 - i;
            uint256 p = pool[r];
            slot = p == 0 ? r : p - 1;
            uint256 l = pool[last];
            pool[r] = (l == 0 ? last : l - 1) + 1;
        }
    }

    /// @notice Tier (true = Genesis) and artwork id for a slot.
    function decode(uint256 slot) internal pure returns (bool genesis, uint16 artwork) {
        if (slot < GENESIS_SLOTS) return (true, uint16(40 + 1 + slot)); // genesis-41 .. genesis-77
        return (false, uint16(slot - GENESIS_SLOTS + 1)); // standard-1 .. standard-423
    }
}
