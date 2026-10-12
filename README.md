# BMC Illuminati Pass (BMCPASS)

500-piece Ethereum mainnet ERC-721 collection minted by permanently burning BMC
(`0x38224239f2BDae357D47cb864BC533d7f72dF961`) through `burnFrom`. 77 Genesis pieces (IPFS PNG),
423 Standard pieces (fully on-chain SVG). Mystery outcomes are decided by **one** Chainlink VRF v2.5
random word requested only after the sale is closed.

**Status: not deployed.** Nothing in this repository broadcasts a transaction, pays a service, or
requests a token approval. Deployment goes through the IdentityMD launch factory after review; see
`docs/READINESS.md`.

## Layout

| Path | What |
| --- | --- |
| `src/BMCIlluminatiPass.sol` | The collection contract (ERC721 + Ownable + ReentrancyGuard, VRF v2.5 consumer). |
| `src/MysteryDraw.sol` | Internal library: seed-driven draw without replacement over the 460 mystery outcomes. |
| `src/StandardArt.sol` | Internal library rendering the 423 Standard SVGs and their traits. |
| `src/interfaces/IBMCToken.sol` | Minimal BMC interface (`burnFrom`, `decimals`, ...). |
| `script/Deploy.s.sol` | Local rehearsal script; mainnet addresses are constants. Not used by the launch. |
| `test/` | Foundry tests (72, including a run against Chainlink's official `VRFCoordinatorV2_5Mock` and three mainnet-fork tests). |
| `artwork/genesis/` | The 77 Genesis PNGs, `genesis-01.png` .. `genesis-77.png`. |
| `artwork/tools/generate_genesis.py` | Deterministic generator for the Genesis PNGs (Pillow). |
| `website/` | Static mint site "bmc-pass" (no build step, no dependencies). |
| `ADAPTATION.md` | Every change made for the launch and the audit remediation, with the rule or finding behind it. |
| `docs/SECURITY-REVIEW.md` | Independent re-review: findings, residual risks, trust assumptions. |
| `docs/TEST-RESULTS.md` | Recorded `forge test` output, fork run, gas measurements. |
| `docs/READINESS.md` | Deployment configuration, owner checklist, cost and scope, readiness verdict. |
| `lib/` | Vendored dependencies as plain files: OpenZeppelin 5.1.0, forge-std 1.9.6, Chainlink contracts 1.4.0 (VRF v2.5 subset). |

## Mint mechanics

- **Phase 1, ids 1-40.** `mintGenesis()` burns 1,000,000 BMC and mints the next id. Id 1 is
  Legendary Genesis; ids N get `genesis-NN.png`. Strictly sequential.
- **Phase 2, ids 41-500.** `mintMystery()` burns 350,000 BMC and mints a pending-reveal NFT. Price is
  identical whatever the result. **No randomness is requested per mint.**
- **Sale close.** `saleClosed()` is true when all 500 are minted, or when 30 days
  (`SALE_IDLE_TIMEOUT`) pass without any mint **once at least one mystery token exists**. The idle
  clock starts at the first mystery mint, not at the 40th Genesis mint: with exactly 40 minted the
  sale stays open however long it is idle, so a closed sale always has something to reveal. No
  transaction is needed and nobody can close the sale earlier.
- **Seed.** Once the sale is closed, anyone calls `requestSeed()`: one VRF v2.5 request (500,000
  callback gas, 3 confirmations, paid in ETH from the fixed subscription, 500 gwei lane). The
  coordinator's callback stores the first word delivered for any request this contract made.
- **Outcomes.** Mystery token `41 + i` is step `i` of a Fisher-Yates draw without replacement over 37
  Genesis (`genesis-41..77`) and 423 Standard outcomes, keyed by the seed. The outcome is a pure
  function of the seed, so `tokenURI`, `tierOf` and `artworkIdOf` are final in the same block the seed
  lands. Every mystery mint has the same 37/460 Genesis chance regardless of mint position or how
  many were sold.
- **Materialization.** `finalizeReveals(maxCount)` (anyone) writes outcomes into storage in mint
  order and emits `Revealed`, making views O(1) for indexers. It changes nothing visible.
- **Totals.** 40 x 1,000,000 + 460 x 350,000 = 201,000,000 BMC maximum burned.

Public views: `ownerOf`, `tierOf`, `artworkIdOf`, `revealStatusOf`, `saleClosed`,
`seedRequestAvailableAt` (0 while it cannot be predicted, i.e. no mystery token yet or seed already
set), `lastSeedRequestAt`, `lastSeedRequestAtOf`, `seedSet`, `seed`, `seedRequestId`, `seedRequestCount`, `totalMinted`,
`totalSupply`, `remainingSupply`, `remainingMysteryMints`, `pendingReveals`, `remainingMysteryGenesis`,
`remainingMysteryStandard`, `currentPrice`, `totalBurned`, `tokenURI`, `standardSVG`, `genesisImagesCID`.

## Unavailable randomness and recovery

Chainlink drops a request it cannot fulfil (for example an unfunded subscription) after about 24
hours. The contract's rules, all permissionless:

- If no word has arrived 36 hours (`SEED_REQUEST_TIMEOUT`) after the latest request charged to the
  fixed subscription, anyone may call `requestSeed()` again.
- `requestSeedWith(subscriptionId, keyHash)` lets anyone pay for the seed from any VRF v2.5
  subscription that lists the pass as a consumer, on any gas lane the coordinator has a proving key
  for (checked on-chain through `s_provingKeys`), should the fixed subscription or lane be unusable.
  The 36-hour timeout is tracked **per subscription** (`lastSeedRequestAtOf`): a request charged to
  someone else's subscription, funded or not, never delays `requestSeed()`. The fixed subscription
  can only be moved to another lane once the coordinator no longer registers the default lane, so a
  stranger cannot choose a more expensive lane at its expense.
- **First delivered word wins.** Whichever outstanding request is fulfilled first sets the seed; every
  later or repeated delivery is ignored and logged (`SeedDeliveryIgnored`). Once the seed is set no
  further request is possible.
- There is no fallback randomness and no owner path. If Chainlink never answers, tokens stay pending;
  this is a stated dependency on Chainlink, bounded by the ability of anyone to fund and re-request.
- **For holders of pending tokens.** The fulfilment transaction carries the VRF proof, from which the
  word (and so every outcome) can be computed by anyone watching the public mempool before it is
  included. Delist pending tokens from the moment a request is outstanding until `seedSet()` is true.

## Privileged powers

| Power | Who | Effect |
| --- | --- | --- |
| `transferOwnership` / `renounceOwnership` | owner | Standard OpenZeppelin Ownable. The owner has **no other function**: no configuration, mint, reroll, artwork assignment, metadata edit, price change, pause, withdrawal or upgrade. Ownership only matters for marketplace collection pages. |
| VRF subscription admin | subscription owner on the Chainlink coordinator | Add the pass as consumer, fund with ETH. Required once before the seed can be fulfilled; anyone can fund. |

The contract is not a proxy; coordinator, subscription id, gas lane, request parameters and the
images CID are fixed at deployment.

## Deployment

Constructor: `(address initialOwner, address bmcToken, address vrfCoordinator, uint256 subscriptionId)`.
Mainnet values: BMC `0x38224239f2BDae357D47cb864BC533d7f72dF961`, coordinator
`0xD7f86b4b8Cae7D942340FF628F82735b7a20893a`, subscription
`27852459484169864437638942739291618120641810244677084392617474192083559562985`. Constants inside the
contract: key hash `0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b` (500 gwei
lane), callback gas 500,000, confirmations 3, native payment, images CID
`bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u`. All verified against mainnet on
2026-10-12; see `docs/READINESS.md`.

### After launch (subscription owner)

1. On vrf.chain.link (Ethereum mainnet), **add the deployed pass address as a consumer** of the
   subscription and **fund it with ETH** (the request pays in native token). Do this before the sale
   closes. Nothing is requested until then, so a late setup only delays the seed.
2. Put the pass address in `website/config.js` (`PASS_ADDRESS`) and host `website/` with `artwork/`
   beside it (or point the gallery at IPFS).
3. When `saleClosed()` is true, anyone (the site has a button) calls `requestSeed()`. Then anyone
   calls `finalizeReveals(50)` repeatedly to materialize the outcomes for indexers.

## Website (bmc-pass)

Static files, no build. Connects MetaMask/Rabby over EIP-1193, encodes calls locally (selectors
computed with an inline keccak-256). Shows BMC balance and allowance, phase, price, remaining
supply, total burned, sale and seed status, Genesis #1 showcase, preview gallery, reveal lookup,
Etherscan links, and explanations of gas, burning and VRF. Two-step approve-then-mint with exact
amounts (no infinite approvals). Buttons to request the seed and to materialize reveals.

## Assumptions

- BMC `burnFrom` follows OpenZeppelin `ERC20Burnable` (exercised against the live token on a mainnet
  fork; guarded on-chain by exact supply/balance deltas).
- 18 decimals, prices expressed as `1_000_000e18` and `350_000e18`.
- Modulo bias of `word % remaining` with a 256-bit word and `remaining <= 460` is negligible (< 2^-247).
- The artwork is original generated vector-style cartoon art; it is not derived from any existing character.

## Testing

```bash
forge build && forge test
MAINNET_RPC_URL=<ethereum mainnet rpc> forge test --match-contract BMCMainnetForkTest
python3 artwork/tools/generate_genesis.py artwork/genesis   # regenerates identical PNGs
```
