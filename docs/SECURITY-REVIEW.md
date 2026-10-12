# Security review — BMC Illuminati Pass

Scope: `src/BMCIlluminatiPass.sol`, `src/StandardArt.sol`, `script/Deploy.s.sol`, `website/`.
Reviewed against the ethskills security checklist supplied with the task. This review was done
by the implementing contributor; it is **not** an independent audit. An adversarial review by a
separate contributor is still required before mainnet (open item O-1).

Tools run: `forge build`, `forge test` (43 tests incl. a 500-mint simulation and fuzzing), manual
review. Slither and Mythril were not available in this environment.

## Findings

| Id | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| F-1 | Medium (design) | Permissionless finalization of stored randomness lets a caller pick the order in which concurrently pending tokens are drawn from a shared pool, which changes outcomes. | Reveals are finalized strictly in mint order (`finalizeReveals`); order is fixed at mint time. Test `test_FinalizationOrderCannotBeChosen`. |
| F-2 | Medium | Finalizing inside the VRF callback can run out of gas; a reverting callback makes the coordinator mark the request fulfilled with the word lost (no retry in v2.5). | The callback stores the word first, then attempts a gas-aware batch via `try this.finalizeReveals(n)`; failure never discards the word. Tests `test_CallbackBatchIsGasAware`, `test_PermissionlessFinalizationWhenCallbackGasTooLow`. |
| F-3 | Medium | Inheriting Chainlink's `VRFConsumerBaseV2Plus` would give the owner `setCoordinator`, a path to point fulfilment at an attacker-controlled coordinator (reroll by proxy). | Not inherited. `rawFulfillRandomWords` is implemented directly with an **immutable** coordinator check. Test `test_OnlyCoordinatorCanFulfill`. |
| F-4 | Medium | A token whose `burnFrom` moves rather than destroys tokens, or has non-18 decimals, would charge the wrong price or not burn. | `_burnExact` checks `decimals()==18` and that both `totalSupply` and payer balance fell by exactly the price. Tests `test_RevertWhenTokenDoesNotActuallyBurn`, `test_RevertWhenTokenDecimalsUnexpected`. |
| F-5 | Low | Reentrancy through `onERC721Received` during `_safeMint`. | CEI ordering plus `nonReentrant` on both mint functions; reentrant mint reverts and rolls back the burn. Tests `test_Reentrancy*`. |
| F-6 | Low | Repeated delivery of the same request id (misbehaving coordinator) could overwrite randomness. | Deliveries for tokens not in `AwaitingRandomness` are ignored. Test `test_FulfillRevealsAndLocksMetadata`. |
| F-7 | Low | Deploying with a placeholder CID would freeze wrong metadata. | No CID in constructor; set once by owner, minting blocked until set. Tests `test_CIDSetOnce`, `test_DeployScriptConfig`. |
| F-8 | Info | Contract runtime is 23,529 bytes, 1,047 bytes under the EIP-170 limit. | Any future change must re-check `forge build --sizes`. |
| F-9 | Info | `word % remaining` modulo bias. | With a 256-bit word and `remaining <= 460`, bias < 2^-247. Accepted. |
| F-10 | Info | Chainlink VRF v2.5 fulfilment order is chosen by VRF nodes. | Outcome depends only on the stored word and in-order processing, so node ordering of deliveries does not change results. |

## Checklist walk-through

- Access control: only `setGenesisImagesCID` (once) and `setVRFConfig` are owner-gated; no mint, withdraw, pause or upgrade functions exist.
- Reentrancy: `nonReentrant` + CEI on `mintGenesis`, `mintMystery`; `finalizeReveals` makes no external calls.
- Decimals: constant price in 18-decimal units with an on-chain decimals check.
- Oracle/randomness: Chainlink VRF v2.5 only; no `block.timestamp`, `blockhash`, `prevrandao` or user input in the draw.
- Return values: `burnFrom` has no return value; correctness is verified by supply and balance deltas instead.
- Input validation: zero-address constructor guard, empty-CID guard, bounded VRF config.
- Events: CID set, VRF config, mints, randomness stored, reveals.
- Incentives: `finalizeReveals` is permissionless; funding the VRF subscription is permissionless.
- No infinite approvals: the website approves the exact price per mint.
- No proxies, no delegatecall, no signatures, no swaps.
- Tested edge cases: sold out, phase boundaries, allowance/balance failures, failed VRF request rolls back burn, unfunded subscription keeps token pending until funded, full mint-out with shuffled fulfilment.

## Open items before mainnet

- **O-1** Independent adversarial review by a separate contributor.
- **O-2** Run Slither / Mythril and an extended fuzz campaign (`forge test --fuzz-runs 10000`).
- **O-3** Exercise `burnFrom` against the live BMC token on a mainnet fork with a funded account (the on-chain guard fails closed if semantics differ).
- **O-4** Explorer source verification after deployment.
- **O-5** Decide whether the owner key should be a multisig (recommended) and whether to renounce after configuration (freezes VRF config).
