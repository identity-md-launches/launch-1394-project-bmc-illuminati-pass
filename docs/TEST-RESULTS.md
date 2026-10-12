# Foundry test results

Recorded 2026-10-12 (revision after the independent review) with forge 1.8.3, solc 0.8.26, the
project's own `foundry.toml` (default profile, fuzz runs 64). Command: `forge test` with an empty
environment.

```
Ran 3 tests for test/BMCMainnetFork.t.sol:BMCMainnetForkTest
[SKIP] test_RealBMCGenesisAndMysteryBurn() (gas: 0)
[SKIP] test_RealCoordinatorAcceptsRequestAndCallbackFitsGasLimit() (gas: 0)
[SKIP] test_RealCoordinatorConfigurationMatchesContract() (gas: 0)
Suite result: ok. 0 passed; 0 failed; 3 skipped; finished in 242.61µs (54.47µs CPU time)
Ran 5 tests for test/ChainlinkMockIntegration.t.sol:ChainlinkMockIntegrationTest
[PASS] test_ExpiredRequestIsRecoveredByPermissionlessReRequest() (gas: 1168411)
[PASS] test_NotAConsumerRevertsWithoutStateChange() (gas: 922062)
[PASS] test_RecoveryPathRefusedWhenCoordinatorHasNoKeyRegistry() (gas: 545030)
[PASS] test_RequestAndFulfilThroughChainlinkMockWithinCallbackGas() (gas: 922654)
[PASS] test_UnfundedSubscriptionKeepsSeedPendingUntilFunded() (gas: 922826)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 4.91ms (1.42ms CPU time)
Ran 15 tests for test/VRFRecovery.t.sol:VRFRecoveryTest
[PASS] test_CallbackRevertingOnUnknownRequestDoesNotTouchState() (gas: 367828)
[PASS] test_CoordinatorRejectionLeavesNoTrace() (gas: 382443)
[PASS] test_DefaultLaneAcceptedWhenRegistryUnavailable() (gas: 342431)
[PASS] test_DefaultLaneIsCheckedAgainstTheRegistryWhenAvailable() (gas: 402785)
[PASS] test_ExpiredRequestReRequestedAfterTimeoutByAnyone() (gas: 806062)
[PASS] test_FailedCallbackLeavesSeedUnsetAndIsRecoverable() (gas: 653125)
[PASS] test_FirstDeliveredWordWinsRegardlessOfRequestOrder() (gas: 673933)
[PASS] test_OverlappingRequestsFirstDeliveredWordWins() (gas: 1414490)
[PASS] test_OwnerCannotRerollRedirectOrPreview() (gas: 969054)
[PASS] test_RecoveryFromAnotherLaneOrSubscription() (gas: 596539)
[PASS] test_SeedCannotBeRequestedBeforeSaleCloses() (gas: 10776894)
[PASS] test_StrangerCannotMoveTheConfiguredSubscriptionToAnotherLane() (gas: 794171)
[PASS] test_TimeoutIsEnforcedPerSubscription() (gas: 956120)
[PASS] test_UnfundedForeignSubscriptionNeverBlocksTheConfiguredSubscription() (gas: 1815761)
[PASS] test_UnregisteredLaneIsRefusedBeforeAnyRequest() (gas: 85605)
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 10.22ms (6.41ms CPU time)
Ran 42 tests for test/BMCIlluminatiPass.t.sol:BMCIlluminatiPassTest
[PASS] testFuzz_SingleRevealAlwaysInInventory(uint256) (runs: 64, μ: 11268385, ~: 11266683)
[PASS] test_CallbackGasIsFarBelowLimit() (gas: 11048740)
[PASS] test_Constants() (gas: 116576)
[PASS] test_ConstructorMakesNoExternalCall() (gas: 20196)
[PASS] test_ConstructorRejectsZeroArguments() (gas: 8562)
[PASS] test_DeployScriptConfig() (gas: 10909638)
[PASS] test_DeployScriptRequiresOwner() (gas: 5870098)
[PASS] test_ExcessAllowanceOnlyBurnsPrice() (gas: 363933)
[PASS] test_FinalizeBeforeSeedDoesNothing() (gas: 10739200)
[PASS] test_FirstMinterGetsLegendaryGenesis1() (gas: 2107992)
[PASS] test_Full500MintSimulation() (gas: 380515010)
[PASS] test_GenesisPhaseNeverClosesByIdleTime() (gas: 624288)
[PASS] test_GenesisRevertsAfterPhase1() (gas: 10642122)
[PASS] test_IdleTimeDoesNotCloseTheSaleBeforeTheFirstMysteryMint() (gas: 11147876)
[PASS] test_Mints2To40AreSequentialGenesis() (gas: 14716383)
[PASS] test_MysteryRevertsDuringPhase1() (gas: 477985)
[PASS] test_NoOwnerConfigurationSurface() (gas: 127132)
[PASS] test_OnlyCoordinatorCanFulfill() (gas: 11067643)
[PASS] test_PartialSaleStillDrawsFromTheFullPool() (gas: 63120952)
[PASS] test_PendingMetadataIsNeutral() (gas: 13615668)
[PASS] test_PendingTokenIsTransferable() (gas: 10775355)
[PASS] test_Phase1CostsExactlyOneMillion() (gas: 412338)
[PASS] test_Phase2CostsExactly350kAndMakesNoVRFRequest() (gas: 11111639)
[PASS] test_RedeliveryAndSecondRequestCannotReroll() (gas: 15858001)
[PASS] test_ReentrancyGenesisBlocked() (gas: 899490)
[PASS] test_ReentrancyMysteryBlocked() (gas: 11275108)
[PASS] test_RevertInsufficientAllowance() (gas: 179307)
[PASS] test_RevertInsufficientBalance() (gas: 193201)
[PASS] test_RevertNoAllowance() (gas: 144210)
[PASS] test_RevertWhenTokenDecimalsUnexpected() (gas: 728551)
[PASS] test_RevertWhenTokenDoesNotActuallyBurn() (gas: 744995)
[PASS] test_SaleClosesAfterIdleTimeoutAndEveryMintResetsIt() (gas: 11004090)
[PASS] test_SaleClosesWhenSoldOut() (gas: 103129476)
[PASS] test_SeedDeliveryFinalizesMetadataInTheSameTransaction() (gas: 32581947)
[PASS] test_SeedRequestRevertsWhileSaleOpen() (gas: 10786224)
[PASS] test_SeedRequestUsesConfiguredParameters() (gas: 11016993)
[PASS] test_StandardArtCombinationsUnique() (gas: 1487525)
[PASS] test_StandardArtCoversEveryTrait() (gas: 744031)
[PASS] test_StandardArtRendersWithoutGenesisTraits() (gas: 30070001)
[PASS] test_StandardMetadataAfterReveal() (gas: 23314609)
[PASS] test_TransfersAreStandard() (gas: 491750)
[PASS] test_ViewsRevertForNonexistent() (gas: 45867)
Suite result: ok. 42 passed; 0 failed; 0 skipped; finished in 930.12ms (1.45s CPU time)
Ran 6 tests for test/RarityFairness.t.sol:RarityFairnessTest
[PASS] testFuzz_DrawIsAPermutation(uint256) (runs: 64, μ: 1306107, ~: 1306107)
[PASS] testFuzz_LibraryMatchesPrototypeAtEveryStep(uint256) (runs: 64, μ: 6504829, ~: 6504949)
[PASS] test_DrawIsAPermutationForFixedSeeds() (gas: 4071573)
[PASS] test_EveryMintPositionHasTheSameGenesisOdds() (gas: 501994473)
[PASS] test_FirstAndLastPositionsAreNotPrivileged() (gas: 312385964)
[PASS] test_LibraryMatchesPrototypeForAllSteps() (gas: 655702503)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 1.29s (2.08s CPU time)
Ran 5 test suites in 1.29s (2.24s CPU time): 68 tests passed, 0 failed, 3 skipped (71 total tests)
```

(The run also included the reviewer's proof copied under `test/scratch/`, which is deleted before
submission: `ForeignSubscriptionBlocksSeedTest` 1 passed. Totals with it: 69 passed, 3 skipped, 72.)

## Ethereum mainnet fork (real BMC token and real Chainlink VRF v2.5 coordinator)

Command: `MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com forge test --match-contract BMCMainnetForkTest`
(public RPC, 2026-10-12, re-run after the revision). Without `MAINNET_RPC_URL` these three tests are
skipped, which is what the log above shows.

```
Ran 3 tests for test/BMCMainnetFork.t.sol:BMCMainnetForkTest
[PASS] test_RealBMCGenesisAndMysteryBurn() (gas: 19639100)
[PASS] test_RealCoordinatorAcceptsRequestAndCallbackFitsGasLimit() (gas: 20262385)
[PASS] test_RealCoordinatorConfigurationMatchesContract() (gas: 89223)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 7.52s (14.57s CPU time)
Ran 1 test suite in 7.53s (7.52s CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
```

What the fork run proves:

- `burnFrom` on the live BMC token (0x38224239f2BDae357D47cb864BC533d7f72dF961) spends the allowance
  and reduces `totalSupply` by exactly the price, at both 1,000,000 BMC and 350,000 BMC; the pass mints
  token 1 and token 41 against it.
- The live coordinator (0xD7f86b4b8Cae7D942340FF628F82735b7a20893a) reports `LINK()` as the mainnet
  LINK token, lists the contract's key hash in `s_provingKeyHashes` with `s_provingKeys` returning
  `(exists = true, maxGas = 500 gwei)`, and rejects a hash one digit off.
- Subscription 27852459484169864437638942739291618120641810244677084392617474192083559562985 exists and
  is owned by 0x83027AD9d0D5374335086c539dADD1db983441B0 (the launch owner).
- With the pass added as a consumer (fork-local prank of the subscription owner), the real
  `requestRandomWords` accepts the request with the contract's fixed parameters and records it as
  pending; without the consumer entry the request reverts and leaves no state behind.
- The callback, invoked from the coordinator address with exactly the 500,000 gas limit, stores the seed.

## Gas measurements (local, MockVRFCoordinator, `test/scratch/Gas.t.sol`, not committed)

Measured on the first version. The revision replaces one storage-slot write in `requestSeed` with a
mapping write (same cost class), adds one `s_provingKeys` staticcall only on the configured
subscription's lane-change path, and does not touch the callback or the mints.

| Operation | Gas |
| --- | --- |
| `mintGenesis` (first / later) | 172,098 / 106,419 |
| `mintMystery` | 60,416 |
| `requestSeed` (includes the coordinator's `requestRandomWords`) | 145,212 |
| `rawFulfillRandomWords` storing the seed | 47,724 |
| `rawFulfillRandomWords` for a superseded request (ignored) | 3,232 |
| `tierOf` view before materialization, token 41 / token 500 | 8,392 / 462,137 |
| `tokenURI` view before materialization, token 500 | 749,870 |
| `finalizeReveals(1)` / `finalizeReveals(50)` | 93,778 / 3,638,826 |
| `tierOf` view after materialization | 1,634 |

The callback uses under 10% of the 500,000 gas limit; the coordinator's `maxGasLimit` is 2,500,000.

## Contract size

`forge build --sizes` after the revision: BMCIlluminatiPass runtime 24,107 bytes (469 bytes under the
EIP-170 limit), init code 25,113 bytes.

## Proof tests

The two proof tests supplied with the audit (`Proof_4fba7786d61d`, head-of-line freeze, and
`Proof_97efd45b2641`, unregistered key hash) were run against the original contract in a scratch
directory and failed with their expected messages, confirming both findings reproduce. They target
functions the redesign removed (`setGenesisImagesCID`, `setVRFConfig`, per-mint requests) and so do
not compile against the new contract; `test/VRFRecovery.t.sol` and `test/BMCIlluminatiPass.t.sol`
cover the same scenarios against the new design.

The proof supplied with the independent review (`Proof_2d181f82390c`, foreign unfunded subscription
blocks `requestSeed()`) failed on the first version of the single-seed contract with
`SeedRequestPending(1762721600)` and passes on this revision (log above, 304,235 gas).

## Launch rehearsal

`.imd/reads/protected/evm_contracts/Contracts.protected.t.sol` was run locally (after the revision)
with the real creation code and constructor arguments `(0x83027ad9d0d5374335086c539dadd1db983441b0,
BMC, coordinator, subscription id)` on chain id 1 with no other contract deployed: the constructor
succeeds, the runtime is within EIP-170 and contains no DELEGATECALL, CALLCODE or SELFDESTRUCT.
