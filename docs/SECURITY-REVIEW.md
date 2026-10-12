# Security re-review — BMC Illuminati Pass, single-seed design

Scope: `src/BMCIlluminatiPass.sol`, `src/MysteryDraw.sol`, `src/StandardArt.sol`, `script/Deploy.s.sol`,
`website/`, the Chainlink VRF v2.5 integration and the mainnet configuration. Reviewed against the
ethskills security checklist and the solidity-security-review questions supplied with the task, and
against the eight findings of the previous IdentityMD audit (all reproduced or accepted; see
`ADAPTATION.md`). This review was written by the contributor who implemented the remediation; an
adversarial reviewer who did not write the code should read it before deployment (open item O-1).

Tools run: `forge build`, `forge test` (72 tests, fuzzing at 64 runs), three mainnet-fork tests
against the live BMC token and coordinator, the launch's protected rehearsal, manual review.
Slither and Mythril are not available in this environment and were not run (open item O-2).

Revision 2026-10-12: an independent reviewer on another machine reported four findings against the
first version of this design (R-11 to R-14 below). All four reproduced; the three with code impact are
fixed and tested, the fourth is documented (residual 9). The proof supplied with R-11 fails on the
first version and passes on this one.

## Design summary

- Mints never touch the coordinator. A mystery mint burns BMC and mints a pending token; nothing
  else can fail or expire.
- The sale closes by rule (sold out, or 30 days idle once at least one mystery token exists). Nobody
  can close it, and it cannot close with nothing to reveal.
- After close, anyone requests one VRF word. The callback only stores the first delivered word.
- Outcomes are a pure function of the seed; the views evaluate it, so the seed and the metadata
  become public in the same transaction.
- Recovery: re-request after 36 hours, from the fixed subscription or from any subscription that
  lists the pass as consumer, on any registered lane. The timeout is per subscription, so no
  subscription can delay another. First delivered word wins.
- The owner has no on-chain power.

## Findings

| Id | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| R-1 | High (previous audit 4fba7786) | Per-token requests with strict in-order finalization: one dead request froze every later reveal. | Removed by design. One seed, no ordering dependency. Tests: `VRFRecoveryTest`. |
| R-2 | Medium (97efd45b, 655c1be5) | BMC burned for requests the coordinator would never fulfil (unregistered lane, unfunded subscription, 24-hour expiry). | No burn depends on a request. Key hash is a verified constant and checked against `s_provingKeys` before every request. Tests: `test_UnregisteredLaneIsRefusedBeforeAnyRequest`, `test_DefaultLaneIsCheckedAgainstTheRegistryWhenAvailable`, fork `test_RealCoordinatorConfigurationMatchesContract`. |
| R-3 | Medium (8474f6bc) | Post-deployment owner configuration; nothing mintable until the owner acted. | All parameters constant or constructor arguments; the constructor makes no external call. Tests: `test_DeployScriptConfig`, `test_ConstructorMakesNoExternalCall`, launch rehearsal. |
| R-4 | Low (3533fc46) | Random word public before metadata was final. | Views derive outcomes from the seed directly. Test: `test_SeedDeliveryFinalizesMetadataInTheSameTransaction`. |
| R-5 | Low (a2e10c39) | Single-step ownership could strand an owner power. | No owner power remains; renouncing mid-flow changes nothing (`test_OwnerCannotRerollRedirectOrPreview`). |
| R-6 | Low (new) | A coordinator that lacks `s_provingKeys` (test mocks, a future coordinator version) cannot have the lane validated. | Default lane is accepted unchecked only in that case; the recovery path, which chooses a lane, requires proof of registration. On mainnet the registry exists (fork test). Accepted. |
| R-7 | Info (new) | `tierOf`/`tokenURI` before materialization cost up to ~0.46M / ~0.75M gas for token 500 (memory draw of up to 460 steps). | View-only cost, well under `eth_call` limits; `finalizeReveals` makes them O(1). On-chain callers of `tierOf` should prefer materialized tokens. Accepted and documented. |
| R-8 | Info | Reentrancy via `onERC721Received` during `_safeMint`. | Checks-effects-interactions plus `nonReentrant` on both mints; `_requestSeed` is `nonReentrant` too. Tests: `test_Reentrancy*`. |
| R-9 | Info | A token whose `burnFrom` moves rather than destroys, or has non-18 decimals. | `_burnExact` checks decimals and exact supply and balance deltas; verified against the live token on a fork. |
| R-10 | Info | Inheriting Chainlink's `VRFConsumerBaseV2Plus` would expose owner `setCoordinator`. | Not inherited; immutable coordinator check in `rawFulfillRandomWords`. Test: `test_OnlyCoordinatorCanFulfill`. |
| R-11 | Medium (independent review 2d181f82) | One global `lastSeedRequestAt` was written for every accepted request, so a stranger with an unfunded subscription (permissionless on the coordinator; balance checked only at fulfilment) could arm the 36-hour lock first in the block the sale closed and keep `requestSeed()` out, every 36 hours, for one transaction per cycle. Related: a stranger could call `requestSeedWith(SUBSCRIPTION_ID, <1000 gwei lane>)` and raise the configured subscription's price cap. | Timeout tracked per subscription (`lastSeedRequestAtOf`); `SeedRequestPending` only for the same subscription. `requestSeedWith` on the configured subscription with another lane reverts `DefaultLaneStillRegistered` while the default lane is registered. Tests: `test_UnfundedForeignSubscriptionNeverBlocksTheConfiguredSubscription`, `test_TimeoutIsEnforcedPerSubscription`, `test_StrangerCannotMoveTheConfiguredSubscriptionToAnotherLane`; the reviewer's proof passes. |
| R-12 | Low (independent review cdb6cbb3) | The idle clock started at the 40th Genesis mint: a 30-day gap before the first mystery mint closed the sale permanently with 460 unsold and no seed ever requestable. | The idle rule applies only once `totalMinted > 40`; the clock starts at the first mystery mint. Test: `test_IdleTimeDoesNotCloseTheSaleBeforeTheFirstMysteryMint`. |
| R-13 | Low (independent review b269281a) | `seedRequestAvailableAt()` promised a time with exactly 40 minted while every request reverted. | Same condition as `saleClosed()`; returns 0 while no mystery token exists. Same test as R-12. |
| R-14 | Info (independent review 26d244d9) | The residual-risk analysis omitted the public-mempool window before the fulfilment transaction lands. | Residual 9 below; README and site tell holders to delist pending tokens while a request is outstanding. |

## Residual risks (what the design cannot remove)

**1. Selective fulfilment by a VRF node.** A node computes the word before sending the fulfilment
transaction and can see every outcome (the draw is public). It cannot change the word (the proof is
bound to the request's pre-seed and block hash), but it can withhold it. With a single request the
node's only options are "deliver" or "not deliver", and withholding is visible (the request stays
pending, Chainlink's own monitoring fails) and costs the node its reputation and fee. Delay is bounded
by the 36-hour re-request rule.

**2. Overlapping requests.** After a re-request, or when several subscriptions request, two or more
commitments may be outstanding. First delivered word wins, so a late delivery for a superseded request
changes nothing. The residual is that a dishonest node holding a proof for request 1 that it withheld
could, once it sees request 2's word, pick the one it prefers and deliver it first: a one-of-k choice
among k outstanding fulfillable requests, never a free choice of word. From the configured subscription
each extra k costs the node 36 hours of visible non-delivery. Since the timeout is per subscription,
anyone can add to k at once by requesting from their own subscriptions; such a request only counts if
its subscription can pay for fulfilment (an unfunded one reverts at fulfilment and gives the node
nothing to choose from), so widening k costs the stranger real ETH per request and the node still
cannot choose a word, only among words. Honest nodes drop requests after 24 hours, so overlap with an
honest node is only a harmless race. The timeout is deliberately longer than 24 hours. A shorter
timeout would reduce holder waiting time but widen this window; a longer one does the opposite.

**3. Dead request locks the subscription.** The mainnet coordinator never deletes an expired
commitment, so `pendingRequestExists` stays true and the subscription owner cannot `cancelSubscription`
or `removeConsumer` (`PendingRequestExists`) without Chainlink's `ownerCancelSubscription`. This is a
coordinator property, not a pass property. Funds in the subscription are not lost to the pass; they
remain the subscription owner's concern. Recovery via another subscription (`requestSeedWith`) does
not need the first one.

**4. Permissionless paying.** `requestSeedWith` lets anyone pay for the seed from their own
subscription. The payer gains no influence: the word comes from Chainlink, the lane must be
registered on the coordinator, the first delivered word wins, and the 36-hour timeout is tracked per
subscription, so a foreign request (funded or not) never delays `requestSeed()` from the configured
subscription (R-11). The configured subscription cannot be moved to another lane by a stranger while
its lane is registered. What a stranger can still do: spend their own ETH to speed up the reveal, or
open unfunded requests that are never fulfilled and change nothing except widening the set of
outstanding commitments on the coordinator (a funded one adds to residual 2's k).

**5. Coordinator dependency.** If Chainlink VRF on mainnet were decommissioned at the coordinator
address fixed here, no seed would ever arrive and mystery tokens would stay pending. No fallback
randomness exists on purpose (block hashes and `prevrandao` are builder-chosen). Chainlink has kept
the v2.5 coordinator and the three mainnet lanes stable; both were verified live on 2026-10-12.

**6. Sale-close timing.** The 30-day idle rule means a sale that never sells out ends 30 days after its
last mint, once at least one mystery token exists. A buyer can extend the sale by minting (paying
350,000 BMC); they cannot shorten it. Mystery holders therefore wait at most 30 days after the final
mint plus the VRF round trip. With exactly 40 Genesis minted the sale never closes by idle time
(R-12); that state has nothing to reveal and nothing to lose.

**7. Block-timestamp use.** `lastMintAt` and the timeouts use `block.timestamp`. Builder drift of a few
seconds cannot change an outcome: the timestamp gates whether a request may be made, never what the
word is. The 36-hour and 30-day windows dwarf any manipulation range.

**8. Operational.** The seed can only be fulfilled if the subscription owner adds the pass as consumer
and funds it with ETH. A missing consumer entry makes `requestSeed` revert with no state change; an
unfunded subscription makes the request expire and be re-requested until funded (tests against
Chainlink's mock). Neither can burn or lose a holder's BMC.

**9. Public-mempool window before fulfilment.** The coordinator's `fulfillRandomWords(proof, rc,
onlyPremium)` transaction carries the VRF proof in calldata. From the moment the node broadcasts it
until it is included, anyone watching the public mempool can derive the word and, because every
outcome is a pure function of the word (`MysteryDraw.slotAt`) and pending tokens are transferable,
knows which pending ids become Genesis. A searcher can buy those listings, or sell future-Standard
ones, in a bundle placed ahead of the fulfilment transaction in the same block. On-chain state never
disagrees with the metadata; the asymmetry is between mempool visibility and inclusion. No consumer-
side change removes it (a private relay is the node's choice, not the contract's). Guidance, in the
README and on the site: holders should delist pending tokens from the moment a request is outstanding
until `seedSet()` is true; buyers of pending tokens during that window take this risk knowingly.

## Checklist walk-through

- Access control: no owner-only function beyond Ownable's own; `rawFulfillRandomWords` is
  coordinator-only; everything else is permissionless by design.
- Reentrancy: `nonReentrant` on `mintGenesis`, `mintMystery`, `_requestSeed`; `finalizeReveals` and the
  callback make no external calls.
- Arithmetic: no unchecked blocks except loop counters; `uint64` timestamps; modulo bias < 2^-247.
- Randomness: Chainlink VRF only; no block hash, `prevrandao` or user input in the draw; the seed is
  requested only after no mint can change the set of participants.
- Signatures, delegatecall, proxies, selfdestruct: none (rehearsed by the launch's opcode scan).
- Events: mints, seed requested/delivered/ignored, reveals.
- Tests cover: boundaries at the idle deadline (one second before and at), idle time with no mystery
  token, sold out, phase boundaries, allowance/balance failures, failing and reverting callbacks,
  expired and overlapping requests in both delivery orders, foreign unfunded subscriptions racing the
  configured one over three cycles, per-subscription timeouts, the configured subscription's lane rule,
  lane registry present and absent, ownership renounced mid-flow, full 500 mint-out
  with view/materialization consistency, partial sale, fuzzed permutation property, prototype
  equivalence at every step, per-position Genesis odds over hundreds of seeds, live token and
  coordinator on a fork.

Untested edges worth noting: behaviour against a future coordinator that changes the
`s_provingKeys` ABI (R-6 covers today's); a malicious coordinator (out of scope, trust assumption);
mainnet gas prices above 500 gwei at fulfilment time (the lane cap; the node waits for gas to fall).

## Open items before mainnet

- **O-1** Adversarial review by a contributor who did not write this code (the launch's final review).
- **O-2** Slither / Mythril and an extended fuzz campaign (`forge test --fuzz-runs 10000`).
- **O-3** Explorer source verification after deployment.
- **O-4** Subscription owner: add consumer and fund with ETH before the sale can close (see
  `docs/READINESS.md` for the amount).
- **O-5** Confirm assumptions A1–A5 in `ADAPTATION.md` (idle window, re-request timeout, lane, CID,
  subscription id).
