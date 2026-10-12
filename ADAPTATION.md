# Adaptation notes — BMC Illuminati Pass, single-seed VRF remediation

Scope: make the project launchable through the `evm_contracts` factory (one contract,
`BMCIlluminatiPass`, deployed from its bytecode with a nonpayable constructor) and implement the
remediation the previous IdentityMD audit recommended: one Chainlink VRF v2.5 seed requested after the
sale closes, permissionless recovery, first-delivered-word-wins. Everything the brief asked to keep is
kept: 500 maximum, 40 sequential Genesis, 37 mystery Genesis and 423 Standard, Legendary Genesis #1,
prices (1,000,000 / 350,000 BMC) and permanent burning through `burnFrom`.

Build configuration, `lib/`, `remappings.txt`, `.github/` and `.git/` are untouched.

## Changes

| # | File | Change | Required by |
| --- | --- | --- | --- |
| 1 | `src/BMCIlluminatiPass.sol` | Constructor is now `(address initialOwner, address bmcToken, address vrfCoordinator, uint256 subscriptionId)`, four static arguments, no external call, no post-deployment configuration. `setGenesisImagesCID` and `setVRFConfig` removed; the images CID, key hash, callback gas (500,000), confirmations (3) and `nativePayment = true` are constants. | Launch rule: fully configured nonpayable constructor, no initialization calls, constructor must not call another contract. Audit finding 8474f6bc (post-deployment configuration) and the owner-controlled lever behind 97efd45b. |
| 2 | `src/BMCIlluminatiPass.sol` | `mintMystery` no longer requests randomness and no longer returns a request id; it burns, mints and records `lastMintAt`. No request mapping per token. | Brief: single-seed architecture. Audit findings 4fba7786 (head-of-line freeze), 97efd45b (unregistered key hash burns BMC), 655c1be5 (burn before an unfundable request). |
| 3 | `src/BMCIlluminatiPass.sol` | `saleClosed()`: sold out, or `SALE_IDLE_TIMEOUT` (30 days) without a mint once at least one mystery token exists (revision: the clock starts at the first mystery mint, not at the 40th Genesis mint). Pure function of state; mints revert with `SaleIsClosed` afterwards. | Brief: request the seed only after the sale is closed under predefined, permissionless rules. See assumption A1 and revision row 17. |
| 4 | `src/BMCIlluminatiPass.sol` | `requestSeed()` (configured subscription and lane) and `requestSeedWith(subscriptionId, keyHash)` (any subscription listing the pass as consumer, any lane registered on the coordinator). Permissionless; allowed once the sale is closed; again after `SEED_REQUEST_TIMEOUT` (36 hours) per subscription if nothing arrived; never once the seed is set. The key hash is checked against the coordinator's `s_provingKeys` registry before any request. | Brief: recovery mechanism for unavailable randomness; prevent owner-controlled rerolls. Audit 97efd45b (validate the key hash against the coordinator), 655c1be5 (24-hour expiry), be647ffd (overlapping requests). Revision row 16. |
| 5 | `src/BMCIlluminatiPass.sol` | `rawFulfillRandomWords` stores the first word delivered for any request this contract made, emits `SeedDelivered`, and ignores (with `SeedDeliveryIgnored`) every later delivery. No other work in the callback. | Brief: first-delivered-word-wins; failed-callback resistance (the callback cannot run out of its 500,000 gas, measured 47,724). |
| 6 | `src/MysteryDraw.sol` (new) | Internal library: outcome of mystery token `41 + i` is step `i` of a Fisher-Yates draw without replacement over 460 slots keyed by the seed, exactly the project's `BMCPassVRFPrototype.draw` semantics from branch `security/vrf-recovery`. | Brief: reviewed single-seed architecture, rarity preserved (37 Genesis / 423 Standard per seed, each artwork once). |
| 7 | `src/BMCIlluminatiPass.sol` | `tierOf`, `artworkIdOf`, `tokenURI`, `standardSVG` derive the outcome from the seed as soon as it is stored. `finalizeReveals(maxCount)` only materializes outcomes into storage (O(1) views, `Revealed` events). `revealStatusOf` returns `RandomnessStored` for "seed set, not materialized". | Audit finding 3533fc46 (seed public while metadata still says pending): there is no such window any more. |
| 8 | `src/BMCIlluminatiPass.sol` | Ownership kept (single-step `Ownable`) but with no on-chain power. `owner` is a constructor argument filled by `$owner`. | Launch rule: owner from constructor, never `msg.sender`. Audit finding a2e10c39 (single-step ownable): no owner action is needed after deployment, so a lost or mistaken handover cannot block anything; two-step ownership was therefore not added. |
| 9 | `script/Deploy.s.sol` | Passes the subscription id; mainnet constants documented with the verification date. Not used by the launch (kept for local rehearsal). | Constructor change (1). |
| 10 | `test/mocks/MockVRFCoordinator.sol` | Models the mainnet coordinator's `s_provingKeys` registry, request acceptance without validation, consumption of a request whose callback failed, and configurable gas for the callback. | New tests (12). |
| 11 | `test/BMCIlluminatiPass.t.sol`, `test/ChainlinkMockIntegration.t.sol` | Rewritten for the new flow (no owner configuration, no per-mint request, sale close, seed request, materialization, 500-NFT distribution, native-payment funding of Chainlink's own mock). Tests encoding the old behaviour (`test_UnavailableRandomnessStaysPendingNoFallback`, `test_UnfundedSubscriptionKeepsTokenPendingUntilFunded`, `test_MysteryBurnRevertsIfVRFRequestFails`, in-order finalization tests) were replaced because that behaviour is what the audit flagged. | Acceptance: every change tested. |
| 12 | `test/VRFRecovery.t.sol`, `test/RarityFairness.t.sol` (new) | Failed callbacks, expired requests, permissionless re-request, overlapping requests with first-delivered-word-wins in both orders, lane and subscription fallback, unregistered lane refused, no owner reroll or early seed; draw is a permutation for every seed (fuzzed), equals the prototype draw at every step, every mint position has the same Genesis odds. | Brief: tests for failed callbacks, expired requests, recovery, rarity fairness, 500 NFT distribution. |
| 13 | `test/BMCMainnetFork.t.sol` | Skips without `MAINNET_RPC_URL` so `forge test` passes with an empty environment; on a fork verifies live `burnFrom` at both prices, the coordinator's key registry, the subscription owner, request acceptance and the callback within 500,000 gas. | Acceptance: `forge test` passes with the project's configuration. Brief: verify real `burnFrom`, deployment configuration and gas limits. |
| 14 | `website/app.js`, `website/index.html` | Removed the `genesisCIDLocked` read; added sale-closed state, seed status, a "Request VRF seed" button and updated copy. | Interface change (1)–(5). |
| 15 | `README.md`, `docs/SECURITY-REVIEW.md`, `docs/TEST-RESULTS.md`, `docs/READINESS.md`, `docs/PULL-REQUEST.md` | Documentation, independent re-review with residual-risk analysis, execution logs, readiness assessment, PR text. | Brief deliverables. |
| 16 | `src/BMCIlluminatiPass.sol` (revision) | The re-request timeout is kept per subscription: `mapping(uint256 => uint64) lastSeedRequestAtOf` replaces the single `lastSeedRequestAt` storage slot (`lastSeedRequestAt()` is kept as a view of the configured subscription's entry). `SeedRequestPending` only applies to a request charged to the same subscription. `requestSeedWith(SUBSCRIPTION_ID, otherLane)` reverts with `DefaultLaneStillRegistered` while the coordinator still registers `KEY_HASH`. | Independent review finding 2d181f82 (reproduced with the supplied proof): a stranger's unfunded subscription armed the single lock and kept `requestSeed()` out for 36 hours, repeatedly. The lane rule closes the related "stranger picks the 1000 gwei lane for the configured subscription" note. Tests: `test_UnfundedForeignSubscriptionNeverBlocksTheConfiguredSubscription`, `test_TimeoutIsEnforcedPerSubscription`, `test_StrangerCannotMoveTheConfiguredSubscriptionToAnotherLane`; the proof passes. |
| 17 | `src/BMCIlluminatiPass.sol` (revision) | `saleClosed()` applies the idle rule only when `totalMinted > GENESIS_PHASE_SUPPLY`. `NothingToReveal` and its check were removed (unreachable: a closed sale always has a mystery token). | Independent review finding cdb6cbb3 (reproduced): a 30-day gap after the 40th Genesis mint closed the sale permanently with 460 unsold and nothing to reveal. Test: `test_IdleTimeDoesNotCloseTheSaleBeforeTheFirstMysteryMint`; `test_SaleClosesAfterIdleTimeoutAndEveryMintResetsIt` updated. |
| 18 | `src/BMCIlluminatiPass.sol` (revision) | `seedRequestAvailableAt()` uses the same condition as `saleClosed()` (`>` not `>=`) and returns 0 while no mystery token exists; it reads the configured subscription's timeout entry. | Independent review finding b269281a (reproduced): the view promised a request time in a state where every request reverted. Same tests as row 17. |
| 19 | `docs/SECURITY-REVIEW.md`, `README.md`, `website/index.html` (revision) | Residual risk 9: the random word is readable in the public mempool from the fulfilment transaction before it lands, so pending-token listings can be sniped; holders should delist pending tokens while a request is outstanding. Residual 4 corrected (a foreign request can no longer delay the configured one); residual 2 notes that funded foreign requests widen a dishonest node's one-of-k choice. | Independent review finding 26d244d9 (documentation). |

## Audit findings: reproduced or not

| Finding | Reproduced? | Resolution |
| --- | --- | --- |
| 4fba7786 high, head-of-line freeze | Yes: the supplied proof fails against the original code with "token 42 ... frozen behind dead request 41". | No per-token request exists; one seed decides every token. `VRFRecoveryTest` covers an unfulfilled request followed by a permissionless re-request. |
| 97efd45b medium, unregistered key hash | Yes: proof fails with "mint accepted with a key hash the coordinator will never fulfil". | No burn depends on a request. The key hash is a verified constant and is checked against `s_provingKeys` before every request; `test_UnregisteredLaneIsRefusedBeforeAnyRequest`, `test_DefaultLaneIsCheckedAgainstTheRegistryWhenAvailable`, fork test against the real registry. |
| 655c1be5 medium, burn with unfundable subscription | Yes by reading: the original `mintMystery` burned and then requested; Chainlink's mock showed `InsufficientBalance` at fulfilment. | Mint never touches the coordinator (`test_Phase2CostsExactly350kAndMakesNoVRFRequest` mints with a rejecting coordinator). Unfunded-then-funded and expired-then-re-requested flows tested against Chainlink's mock with native funding. |
| 8474f6bc medium, post-deployment configuration | Yes: `test_DeployScriptConfig` on the original asserted that a fresh deployment cannot mint. | Everything is in the constructor or constant; `test_DeployScriptConfig` now asserts a fresh deployment is fully configured, `test_ConstructorMakesNoExternalCall` deploys against code-less addresses. |
| a2e10c39 low, single-step ownable | Yes by reading. | No owner power remains, so the finding has no effect; `test_OwnerCannotRerollRedirectOrPreview` renounces ownership mid-flow and shows nothing changes. Two-step ownership deliberately not added (nothing to protect). |
| 3533fc46 low, public word before finalization | Yes by reading (`CALLBACK_REVEAL_BATCH`, gas-bounded inline finalization). | Outcomes are a pure function of the seed, evaluated by the views; `test_SeedDeliveryFinalizesMetadataInTheSameTransaction`. |
| be647ffd info, residual VRF risks | Not a defect. | Analysed in `docs/SECURITY-REVIEW.md` (selective fulfilment, overlapping requests, locked subscription). |
| 76a42d0f info, mainnet configuration | Re-verified independently on 2026-10-12 (block 26175546): coordinator code and `LINK()`, three registered key hashes, `s_provingKeys` for the 500 gwei lane, subscription exists with 0 balance and no consumer, BMC decimals/selectors/non-proxy. | Fixed constants in the contract; fork tests; `docs/READINESS.md`. |

## Independent review findings (revision): reproduced or not

| Finding | Reproduced? | Resolution |
| --- | --- | --- |
| 2d181f82 medium, foreign unfunded subscription blocks `requestSeed()` | Yes: the supplied proof failed with `SeedRequestPending(1762721600)` on the starting tree. | Per-subscription timeout and the default-lane rule (row 16). Proof passes; three new tests. |
| cdb6cbb3 low, idle clock starts at the 40th Genesis mint | Yes by reading and by the old test's assertion (`seedRequestAvailableAt() == t0 + 30 days` with 40 minted). Judged real: a quiet month between the phases lost the whole mystery phase. | Idle rule only once a mystery token exists (row 17). |
| b269281a low, view promises a time when every request reverts | Yes: same state as above. | View shares the close condition (row 18). |
| 26d244d9 info, mempool window not in the residual-risk analysis | Yes by reading. | Documented (row 19); no code change can remove it. |

## Assumptions the requester should confirm before deployment

- **A1 Sale close rule.** The brief asks for predefined, permissionless close rules but names none. The
  contract closes the sale when sold out, or when 30 days pass without any mint once at least one
  mystery token exists. The 40th Genesis mint does not start the clock: if no mystery token is ever
  minted the sale simply stays open, which costs nothing because there is nothing to reveal. No owner
  close was added, to keep the rule permissionless as the brief says. Change `SALE_IDLE_TIMEOUT`
  before deployment if a different window is wanted.
- **A2 Re-request timeout.** 36 hours, chosen to be longer than Chainlink's 24-hour pending window so an
  honest node has dropped a stale request before a new one is opened.
- **A3 Gas lane.** The 500 gwei lane previously proposed was independently verified as registered and is
  used as the default; the 200 gwei and 1000 gwei lanes are registered too and reachable through
  `requestSeedWith` by anyone if the default lane is ever retired.
- **A4 Images CID.** `bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u` from the requester's
  own fork test is a constant; `genesis-01.png` fetched from that directory through a public gateway
  has the same sha256 as `artwork/genesis/genesis-01.png`. Re-pin before launch and keep it pinned.
- **A5 Subscription id** is a constructor argument (brief value, verified to exist and to be owned by
  the launch owner). It is immutable; if the subscription is ever cancelled, recovery goes through
  `requestSeedWith` with any other subscription that lists the pass as consumer. Such a request has
  its own 36-hour timeout and never delays `requestSeed()`.
