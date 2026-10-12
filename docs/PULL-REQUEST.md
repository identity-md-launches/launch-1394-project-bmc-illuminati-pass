# Pull request: single-seed Chainlink VRF architecture (final security fix)

Base: `main` (and supersedes `security/vrf-recovery`, whose prototype draw this PR adopts).
Do not merge from this task; the launch's final review decides.

## Summary

Replaces the per-mint VRF request design with one seed requested only after the sale closes, under
permissionless rules, with permissionless recovery and first-delivered-word-wins semantics. Fixes
every finding of the previous IdentityMD audit that reproduced (head-of-line freeze, BMC burned for
unfulfillable requests, post-deployment configuration, public word before final metadata, stranded
owner power) and makes the contract deployable by the launch factory in one transaction.

Preserved: 500 maximum, 40 sequential Genesis, Legendary Genesis #1, 37 mystery Genesis and 423
Standard, prices 1,000,000 / 350,000 BMC, permanent burning through `burnFrom`.

## Changes

- `src/BMCIlluminatiPass.sol`: constructor `(owner, bmc, coordinator, subscriptionId)`, constants for
  images CID, key hash (verified 500 gwei lane), callback gas 500,000, confirmations 3, native
  payment; `mintMystery` makes no request; `saleClosed()` by rule; `requestSeed()` /
  `requestSeedWith()`; minimal callback storing the first word; outcomes derived from the seed;
  `finalizeReveals` materializes only. Owner has no on-chain power.
- `src/MysteryDraw.sol`: seed-driven Fisher-Yates draw, same semantics as `BMCPassVRFPrototype.draw`.
- Tests: 72 (failed callbacks, expired requests, recovery, overlapping requests, foreign
  subscriptions racing the configured one, lane and subscription fallback, idle rule with no mystery
  token, rarity fairness, 500-NFT distribution, Chainlink mock with native funding, mainnet fork for
  real `burnFrom` and coordinator configuration). Logs in `docs/TEST-RESULTS.md`.
- `website/`: sale and seed status, request-seed button, updated copy.
- Docs: `ADAPTATION.md`, `docs/SECURITY-REVIEW.md`, `docs/READINESS.md`, `README.md`.

## Revision after the independent review

- Per-subscription re-request timeout (`lastSeedRequestAtOf`): a stranger's unfunded subscription can
  no longer block `requestSeed()` (reviewer proof passes). The configured subscription can only be
  moved to another lane once the coordinator retires its default lane.
- The 30-day idle rule starts at the first mystery mint, not at the 40th Genesis mint, so a quiet
  month between the phases cannot end the sale with nothing to reveal. `seedRequestAvailableAt()`
  returns 0 while it cannot be predicted.
- Residual risk 9 (public-mempool window before fulfilment) documented, with holder guidance.

## Verification

- `forge build`, `forge test`: 69 passed, 3 skipped (fork tests without RPC), 0 failed.
- `MAINNET_RPC_URL=… forge test --match-contract BMCMainnetForkTest`: 3 passed.
- Launch protected rehearsal with real constructor arguments: passed.
- Mainnet reads (block 26175546): coordinator, three registered key hashes, subscription state, BMC.

## Not done here, on purpose

No deployment, no broadcast, no BMC moved, no consumer added, no subscription funded, no workflow
file changed, no merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
