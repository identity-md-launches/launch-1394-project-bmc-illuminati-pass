# Readiness assessment — BMC Illuminati Pass #1356 (single-seed VRF)

Date: 2026-10-12. Scope of this assessment: the code in this repository as adapted for the
IdentityMD `evm_contracts` launch on Ethereum mainnet (chain id 1), owner
`0x83027ad9d0d5374335086c539dadd1db983441b0`. Nothing was deployed, broadcast, funded or added as a
consumer; no BMC was moved or burned.

## Verdict

**Ready for the launch's final independent review and manifest step**, with two operational actions
that the subscription owner must perform after deployment and before the sale closes (consumer entry
and ETH funding), and five assumptions to confirm (A1–A5 in `ADAPTATION.md`). No code blocker remains.

## Deployment configuration (independently verified on mainnet, block 26175546)

| Item | Value | Verification |
| --- | --- | --- |
| Contract | `BMCIlluminatiPass`, runtime 23,893 bytes (683 under EIP-170), no DELEGATECALL/CALLCODE/SELFDESTRUCT | `forge build --sizes`; launch protected rehearsal passed with the real arguments on an empty chain |
| Constructor | `(initialOwner, bmcToken, vrfCoordinator, subscriptionId)` | 4 static arguments, nonpayable, no external call |
| `initialOwner` | `$owner` = `0x83027ad9d0d5374335086c539dadd1db983441b0` | Launch rule; owner has no on-chain power |
| `bmcToken` | `0x38224239f2BDae357D47cb864BC533d7f72dF961` | `name()` "BMC Illuminati", `symbol()` "BMC", `decimals()` 18, supply ~9.907e26, EIP-1967 slot empty, `burnFrom` selector present, no `owner()`/`paused()`; `burnFrom` exercised on a fork at both prices |
| `vrfCoordinator` | `0xD7f86b4b8Cae7D942340FF628F82735b7a20893a` (VRF v2.5) | Code present (48 KB), `LINK()` = `0x514910771AF9Ca656af840dff83E8264EcF986CA`, `s_config` min confirmations 3, max callback gas 2,500,000, native premium 24% |
| `subscriptionId` | `27852459484169864437638942739291618120641810244677084392617474192083559562985` | `getSubscription`: balance 0 LINK, native 0, owner `0x83027AD9d0D5374335086c539dADD1db983441B0`, consumers `[]`, `pendingRequestExists` false |
| Key hash (constant) | `0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b` | `s_provingKeyHashes(2)` equals it; `s_provingKeys` returns `(true, 500 gwei)`; the other registered lanes are `0xc6bf…d45f` (1000 gwei) and `0x8077…3dd9` (200 gwei); a hash one digit off returns `(false, 0)` |
| Callback gas limit | 500,000 | Measured callback: 47,724 gas; fork test drives the callback with exactly 500,000 from the coordinator address |
| Request confirmations | 3 | Equals the coordinator minimum |
| Payment | native (`nativePayment = true`) | Subscription must hold ETH, not LINK |
| Images CID | `bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u` | `genesis-01.png` fetched via gateway.pinata.cloud has sha256 `b35a60c9…` = `artwork/genesis/genesis-01.png` |

## Gas limits

| Operation | Gas | Note |
| --- | --- | --- |
| `mintGenesis` / `mintMystery` | ~106k–172k / ~60k | plus BMC `burnFrom` |
| `requestSeed` | ~145k | includes the coordinator's bookkeeping |
| VRF callback | ~48k of 500,000 | cannot exceed the limit; a failing callback would be re-requestable after 36 h |
| `finalizeReveals(50)` | ~3.6M | 460 tokens in ten batches; `finalizeReveals(409)` measured at 24.1M, so keep batches ≤ 100 |
| `tierOf` / `tokenURI` views before materialization | up to ~0.46M / ~0.75M | `eth_call` only; O(1) after materialization |

VRF fulfilment cost (what the subscription pays): roughly (callback gas used + ~200k verification
overhead) × gas price × 1.24 premium. At 10 gwei that is about 0.003 ETH; the lane's 500 gwei cap
bounds it at about 0.35 ETH for one fulfilment. Fund with margin for a possible re-request. Chainlink's
UI shows the minimum balance it expects for the lane.

## Price and scope for approval (shown before any paid execution)

Nothing in this task spent money. The paid steps that follow, each requiring explicit approval:

1. **Launch deployment** through the IdentityMD factory: one contract, gas for ~24.9 KB of init code
   (estimate 5.0–5.5M gas at deployment; at 10 gwei about 0.05 ETH). Paid by the launch.
2. **Subscription funding** by the subscription owner: recommended 0.5 ETH on the 500 gwei lane
   (covers one fulfilment at the lane cap plus a re-request), adjustable to current gas prices.
3. **Consumer entry**: one `addConsumer` transaction by the subscription owner (~70k gas).

Scope delivered in this PR: single-seed contract, draw library, recovery mechanism, 68 tests with
logs, mainnet fork verification, launch rehearsal, documentation and this assessment. Not in scope:
deployment, broadcasting, funding, consumer entry, merging.

## Owner checklist after deployment

1. Verify the deployed address shows `SUBSCRIPTION_ID()`, `KEY_HASH()`, `GENESIS_IMAGES_CID()` and
   `owner()` as above.
2. On vrf.chain.link: add the pass as consumer; fund with ETH. Before the sale closes.
3. Keep the IPFS directory pinned (re-pin on your own node or pinning service).
4. Set `PASS_ADDRESS` in `website/config.js`; host the site.
5. When `saleClosed()` turns true, call `requestSeed()` (anyone can). Then `finalizeReveals(50)`
   until `pendingReveals()` is 0 (anyone can).
6. If `seedSet()` is still false 36 hours after a request: fund the subscription if needed and call
   `requestSeed()` again, or `requestSeedWith(<your other subscription>, <registered key hash>)`.

## What still needs a human decision

- A1 idle window (30 days) and A2 re-request timeout (36 hours) are constants chosen by the
  contributor because the brief gave none; change them before deployment if wanted.
- Whether to use the 200 gwei lane instead of 500 gwei as the default (cheaper minimum funding,
  slower fulfilment when gas is high). Both are registered; the recovery path can use either.
- Ownership key: a multisig is recommended even though the owner has no on-chain power, because
  marketplaces use `owner()` for collection administration.

## Pull request

The publisher token cannot modify workflows, so `.github/workflows/main.yml` is untouched. The PR
title and body are in `docs/PULL-REQUEST.md`; the IdentityMD publisher opens the PR from the result
branch against `main`. The PR must not be merged by the contributor.
