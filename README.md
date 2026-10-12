# BMC Illuminati Pass (BMCPASS)

500-piece Ethereum mainnet ERC-721 collection minted by permanently burning BMC
(`0x38224239f2BDae357D47cb864BC533d7f72dF961`) through `burnFrom`. 77 Genesis pieces (IPFS PNG),
423 Standard pieces (fully on-chain SVG). Mystery outcomes are drawn without replacement using
Chainlink VRF v2.5.

**Status: not deployed.** Nothing in this repository broadcasts a transaction, pays a service, or
requests a token approval. Mainnet deployment needs the owner's explicit authorization after review.

## Layout

| Path | What |
| --- | --- |
| `src/BMCIlluminatiPass.sol` | The collection contract (ERC721 + Ownable + ReentrancyGuard, VRF v2.5 consumer). |
| `src/StandardArt.sol` | Internal library rendering the 423 Standard SVGs and their traits. |
| `src/interfaces/IBMCToken.sol` | Minimal BMC interface (`burnFrom`, `decimals`, ...). |
| `script/Deploy.s.sol` | Deployment script; mainnet addresses are constants, owner is the only input. |
| `test/` | Foundry tests (43), including a run against Chainlink's official `VRFCoordinatorV2_5Mock`. |
| `artwork/genesis/` | The 77 Genesis PNGs (1024x1024), `genesis-01.png` .. `genesis-77.png`. |
| `artwork/tools/generate_genesis.py` | Deterministic generator for the Genesis PNGs (Pillow). |
| `website/` | Static mint site "bmc-pass" (no build step, no dependencies). |
| `docs/SECURITY-REVIEW.md` | Security review findings and open items. |
| `docs/TEST-RESULTS.md` | Recorded `forge test` output. |
| `lib/` | Vendored dependencies as plain files: OpenZeppelin 5.1.0, forge-std 1.9.6, Chainlink contracts 1.4.0 (VRF v2.5 subset). |

## Pre-deployment checks performed (IMD free check, 2026-10-12)

| Check | Result |
| --- | --- |
| BMC `decimals()` | 18 (read on mainnet). The contract re-checks on every mint and reverts otherwise. |
| BMC `burnFrom` | Selector `0x79cc6790` present in the deployed, non-proxy bytecode (EIP-1967 slot empty); OpenZeppelin `ERC20Burnable` semantics assumed: spend allowance, then burn. The contract verifies after each call that `totalSupply` and the payer balance both dropped by exactly the price. |
| BMC owner / pause | No `owner()` or `paused()` function responds. |
| Chainlink VRF v2.5 coordinator | `0xD7f86b4b8Cae7D942340FF628F82735b7a20893a` has code and reports `LINK() == 0x514910771AF9Ca656af840dff83E8264EcF986CA`. |
| Genesis images CID | **Blocker until set.** Must be produced by uploading `artwork/genesis/` to IPFS. Set once on-chain via `setGenesisImagesCID`; minting is impossible before. |
| VRF subscription | **Blocker until created.** Needs a funded VRF v2.5 subscription with the pass added as consumer; set via `setVRFConfig`. |
| Image generation | Available: Pillow generated the 77 originals deterministically. |

The `burnFrom` behaviour could not be exercised against the live token from this environment (no
funded account); the on-chain mismatch guard makes a wrong assumption fail closed rather than mint.

## Mint mechanics

- **Phase 1, ids 1-40.** `mintGenesis()` burns 1,000,000 BMC and mints the next id. Id 1 is
  Legendary Genesis; ids N get `genesis-NN.png`. Strictly sequential.
- **Phase 2, ids 41-500.** `mintMystery()` burns 350,000 BMC, mints a pending-reveal NFT and opens
  one VRF request. Price is identical whatever the result.
- **Reveal.** The coordinator calls `rawFulfillRandomWords`; the word is stored, then a gas-aware
  batch of reveals runs. Reveals are finalized **in mint order** (41, 42, ...) by anyone through
  `finalizeReveals(maxCount)`. In-order finalization means nobody can influence an outcome by
  choosing the order in which concurrently pending tokens are drawn.
- **Draw.** Virtual Fisher-Yates over 460 slots (37 Genesis `genesis-41..77`, 423 Standard), O(1)
  per draw. Every outcome is assigned exactly once by full mint-out.
- **Tier storage.** Tier and artwork id are stored per token; nothing is inferred from token id.
- **Totals.** 40 x 1,000,000 + 460 x 350,000 = 201,000,000 BMC maximum burned.

Public views: `ownerOf`, `tierOf`, `artworkIdOf`, `revealStatusOf`, `totalMinted`, `totalSupply`,
`remainingSupply`, `remainingMysteryMints`, `pendingReveals`, `remainingMysteryGenesis`,
`remainingMysteryStandard`, `currentPrice`, `totalBurned`, `tokenURI`, `standardSVG`.

## Unavailable randomness

A pending token stays pending until its original request is fulfilled. There is no reroll,
re-request or fallback. Chainlink VRF v2.5 keeps a request pending while the subscription is
unfunded and fulfils it after funding, which anyone can do. The owner changing `setVRFConfig`
cannot touch open requests. If the coordinator were permanently decommissioned, affected tokens
would remain pending forever; this is a stated trust dependency on Chainlink, not a hidden one.

## Privileged powers and operational responsibilities

| Power | Who | Effect | Limits |
| --- | --- | --- | --- |
| `setGenesisImagesCID(cid)` | owner, once | Sets the IPFS directory for Genesis images. | Cannot be changed afterwards; no mint is possible before it is set. |
| `setVRFConfig(subId, keyHash, callbackGas, confirmations, nativePayment)` | owner, any time | Parameters for **future** VRF requests. | Bounded (gas 150k-2.5M, confirmations 3-200). Cannot affect stored randomness or revealed tokens. A bad config only blocks new mystery mints until corrected. |
| VRF subscription admin | subscription owner on the Chainlink coordinator | Add/remove the pass as consumer, fund with LINK or ETH. | Removing the consumer or defunding blocks new requests / delays fulfilment. Anyone can fund. |
| `transferOwnership` / `renounceOwnership` | owner | Standard OpenZeppelin Ownable. | Renouncing freezes the VRF config forever. |

There is no owner mint, airdrop, artwork assignment, metadata edit, price change, pause,
withdrawal or upgrade path. The contract is not a proxy. The coordinator address is immutable.

## Deployment (do not run without explicit authorization)

Constructor: `(address initialOwner, address bmcToken, address vrfCoordinator)`.
Mainnet values: BMC `0x38224239f2BDae357D47cb864BC533d7f72dF961`,
coordinator `0xD7f86b4b8Cae7D942340FF628F82735b7a20893a`.

```bash
forge build
forge test
OWNER=0xYourOwner forge script script/Deploy.s.sol:DeployBMCIlluminatiPass \
  --rpc-url $ETH_RPC --account <keystore> --broadcast --verify
```

Verify source on Etherscan (`forge verify-contract`) before announcing.

### After launch (owner, in this order)

1. **Upload artwork.** Pin `artwork/genesis/` (77 files) as one IPFS directory. Record its CID.
   Check `ipfs://<CID>/genesis-01.png` resolves on at least two gateways.
2. **Set the CID.** `setGenesisImagesCID("<CID>")` once. Minting opens only after this.
3. **Create a VRF v2.5 subscription** at vrf.chain.link (mainnet), fund it (LINK or ETH), add the
   pass address as a consumer.
4. **Set VRF config.** `setVRFConfig(subscriptionId, keyHash, 500000, 3, nativePayment)`.
   Key hash is the gas lane you choose from Chainlink's published mainnet lanes (e.g. the 200/500/1000 gwei lanes);
   500k callback gas lets each callback finalize up to 4 reveals. `nativePayment=true` if funded with ETH.
5. **Website.** Put the pass address in `website/config.js` (`PASS_ADDRESS`) and host `website/`
   with `artwork/` beside it (or point the gallery at IPFS).
6. Keep the subscription funded: 460 requests at mainnet VRF prices. Monitor
   `pendingReveals()`; anyone can call `finalizeReveals(n)` if a callback left stored words.

## Website (bmc-pass)

Static files, no build. Connects MetaMask/Rabby over EIP-1193, encodes calls locally (selectors
computed with an inline keccak-256). Shows BMC balance and allowance, phase, price, remaining
supply, total burned, remaining-inventory odds (marked provisional while reveals are pending),
Genesis #1 showcase, preview gallery, reveal lookup, Etherscan links, and explanations of gas,
burning and VRF delays. Two-step approve-then-mint with exact amounts (no infinite approvals).

## Assumptions

- BMC `burnFrom` follows OpenZeppelin `ERC20Burnable` (verified by selector and non-proxy code;
  guarded on-chain by exact supply/balance deltas).
- 18 decimals, prices expressed as `1_000_000e18` and `350_000e18`.
- Chainlink mainnet VRF v2.5 coordinator and key hashes per Chainlink documentation; the owner
  chooses the gas lane.
- Modulo bias of `word % remaining` with a 256-bit word and `remaining <= 460` is negligible (< 2^-247).
- The artwork is original generated vector-style cartoon art; it is not derived from any existing character.

## Testing

```bash
forge build && forge test && forge fmt --check
python3 artwork/tools/generate_genesis.py artwork/genesis   # regenerates identical PNGs
```
