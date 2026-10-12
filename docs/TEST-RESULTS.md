# Foundry test results

Recorded 2026-10-12 with forge 1.5.1-stable, solc 0.8.26, the project's own `foundry.toml`
(default profile, fuzz runs 64). Command: `forge test` with an empty environment.

```
No files changed, compilation skipped
Ran 3 tests for test/BMCMainnetFork.t.sol:BMCMainnetForkTest
[SKIP] test_RealBMCGenesisAndMysteryBurn() (gas: 0)
[SKIP] test_RealCoordinatorAcceptsRequestAndCallbackFitsGasLimit() (gas: 0)
[SKIP] test_RealCoordinatorConfigurationMatchesContract() (gas: 0)
Suite result: ok. 0 passed; 0 failed; 3 skipped; finished in 1.56ms (267.36µs CPU time)
Ran 5 tests for test/ChainlinkMockIntegration.t.sol:ChainlinkMockIntegrationTest
[PASS] test_ExpiredRequestIsRecoveredByPermissionlessReRequest() (gas: 614312)
[PASS] test_NotAConsumerRevertsWithoutStateChange() (gas: 426409)
[PASS] test_RecoveryPathRefusedWhenCoordinatorHasNoKeyRegistry() (gas: 289113)
[PASS] test_RequestAndFulfilThroughChainlinkMockWithinCallbackGas() (gas: 484387)
[PASS] test_UnfundedSubscriptionKeepsSeedPendingUntilFunded() (gas: 468689)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 32.12ms (7.35ms CPU time)
Ran 12 tests for test/VRFRecovery.t.sol:VRFRecoveryTest
[PASS] test_CallbackRevertingOnUnknownRequestDoesNotTouchState() (gas: 230698)
[PASS] test_CoordinatorRejectionLeavesNoTrace() (gas: 197084)
[PASS] test_DefaultLaneAcceptedWhenRegistryUnavailable() (gas: 203535)
[PASS] test_DefaultLaneIsCheckedAgainstTheRegistryWhenAvailable() (gas: 242256)
[PASS] test_ExpiredRequestReRequestedAfterTimeoutByAnyone() (gas: 494456)
[PASS] test_FailedCallbackLeavesSeedUnsetAndIsRecoverable() (gas: 376125)
[PASS] test_FirstDeliveredWordWinsRegardlessOfRequestOrder() (gas: 413673)
[PASS] test_OverlappingRequestsFirstDeliveredWordWins() (gas: 832224)
[PASS] test_OwnerCannotRerollRedirectOrPreview() (gas: 551040)
[PASS] test_RecoveryFromAnotherLaneOrSubscription() (gas: 362769)
[PASS] test_SeedCannotBeRequestedBeforeSaleCloses() (gas: 9798540)
[PASS] test_UnregisteredLaneIsRefusedBeforeAnyRequest() (gas: 41140)
Suite result: ok. 12 passed; 0 failed; 0 skipped; finished in 61.23ms (21.50ms CPU time)
Ran 42 tests for test/BMCIlluminatiPass.t.sol:BMCIlluminatiPassTest
[PASS] testFuzz_SingleRevealAlwaysInInventory(uint256) (runs: 64, μ: 6227422, ~: 6224769)
[PASS] test_CallbackGasIsFarBelowLimit() (gas: 6129334)
[PASS] test_Constants() (gas: 25466)
[PASS] test_ConstructorMakesNoExternalCall() (gas: 4923292)
[PASS] test_ConstructorRejectsZeroArguments() (gas: 481252)
[PASS] test_DeployScriptConfig() (gas: 10262235)
[PASS] test_DeployScriptRequiresOwner() (gas: 5326519)
[PASS] test_ExcessAllowanceOnlyBurnsPrice() (gas: 265135)
[PASS] test_FinalizeBeforeSeedDoesNothing() (gas: 5961966)
[PASS] test_FirstMinterGetsLegendaryGenesis1() (gas: 1926963)
[PASS] test_Full500MintSimulation() (gas: 266823507)
[PASS] test_GenesisPhaseNeverClosesByIdleTime() (gas: 356802)
[PASS] test_GenesisRevertsAfterPhase1() (gas: 5912202)
[PASS] test_Mints2To40AreSequentialGenesis() (gas: 7970875)
[PASS] test_MysteryRevertsDuringPhase1() (gas: 281013)
[PASS] test_NoOwnerConfigurationSurface() (gas: 38676)
[PASS] test_OnlyCoordinatorCanFulfill() (gas: 6100624)
[PASS] test_PartialSaleStillDrawsFromTheFullPool() (gas: 39161561)
[PASS] test_PendingMetadataIsNeutral() (gas: 8259731)
[PASS] test_PendingTokenIsTransferable() (gas: 5984906)
[PASS] test_Phase1CostsExactlyOneMillion() (gas: 253920)
[PASS] test_Phase2CostsExactly350kAndMakesNoVRFRequest() (gas: 6093732)
[PASS] test_RedeliveryAndSecondRequestCannotReroll() (gas: 9832573)
[PASS] test_ReentrancyGenesisBlocked() (gas: 691032)
[PASS] test_ReentrancyMysteryBlocked() (gas: 6298080)
[PASS] test_RevertInsufficientAllowance() (gas: 103875)
[PASS] test_RevertInsufficientBalance() (gas: 107947)
[PASS] test_RevertNoAllowance() (gas: 81458)
[PASS] test_RevertWhenTokenDecimalsUnexpected() (gas: 5478682)
[PASS] test_RevertWhenTokenDoesNotActuallyBurn() (gas: 5445448)
[PASS] test_SaleClosesAfterIdleTimeoutAndEveryMintResetsIt() (gas: 6036032)
[PASS] test_SaleClosesWhenSoldOut() (gas: 48013856)
[PASS] test_SeedDeliveryFinalizesMetadataInTheSameTransaction() (gas: 26146868)
[PASS] test_SeedRequestRevertsWhileSaleOpen() (gas: 5974033)
[PASS] test_SeedRequestRevertsWithoutMysteryTokens() (gas: 5857106)
[PASS] test_SeedRequestUsesConfiguredParameters() (gas: 6098841)
[PASS] test_StandardArtCombinationsUnique() (gas: 1487525)
[PASS] test_StandardArtCoversEveryTrait() (gas: 744031)
[PASS] test_StandardArtRendersWithoutGenesisTraits() (gas: 30070001)
[PASS] test_StandardMetadataAfterReveal() (gas: 14552801)
[PASS] test_TransfersAreStandard() (gas: 258327)
[PASS] test_ViewsRevertForNonexistent() (gas: 24912)
Suite result: ok. 42 passed; 0 failed; 0 skipped; finished in 4.75s (6.23s CPU time)
Ran 6 tests for test/RarityFairness.t.sol:RarityFairnessTest
[PASS] testFuzz_DrawIsAPermutation(uint256) (runs: 64, μ: 1306107, ~: 1306107)
[PASS] testFuzz_LibraryMatchesPrototypeAtEveryStep(uint256) (runs: 64, μ: 6504198, ~: 6504580)
[PASS] test_DrawIsAPermutationForFixedSeeds() (gas: 4071573)
[PASS] test_EveryMintPositionHasTheSameGenesisOdds() (gas: 501994473)
[PASS] test_FirstAndLastPositionsAreNotPrivileged() (gas: 312385964)
[PASS] test_LibraryMatchesPrototypeForAllSteps() (gas: 655702503)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 6.68s (17.83s CPU time)
Ran 5 test suites in 6.69s (11.52s CPU time): 65 tests passed, 0 failed, 3 skipped (68 total tests)
```

## Ethereum mainnet fork (real BMC token and real Chainlink VRF v2.5 coordinator)

Command: `MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com forge test --match-contract BMCMainnetForkTest`
(public RPC, fork at about block 26175638, 2026-10-12). Without `MAINNET_RPC_URL` these three tests are
skipped, which is what the log above shows.

```
Ran 3 tests for test/BMCMainnetFork.t.sol:BMCMainnetForkTest
[PASS] test_RealBMCGenesisAndMysteryBurn() (gas: 16725632)
[PASS] test_RealCoordinatorAcceptsRequestAndCallbackFitsGasLimit() (gas: 17132007)
[PASS] test_RealCoordinatorConfigurationMatchesContract() (gas: 4959575)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 7.67s (15.12s CPU time)
Ran 1 test suite in 7.68s (7.67s CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
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

`forge build --sizes`: BMCIlluminatiPass runtime 23,893 bytes (683 bytes under the EIP-170 limit),
init code 24,878 bytes.

## Audit proof tests

The two proof tests supplied with the audit (`Proof_4fba7786d61d`, head-of-line freeze, and
`Proof_97efd45b2641`, unregistered key hash) were run against the original contract in a scratch
directory and failed with their expected messages, confirming both findings reproduce. They target
functions the redesign removed (`setGenesisImagesCID`, `setVRFConfig`, per-mint requests) and so do
not compile against the new contract; `test/VRFRecovery.t.sol` and `test/BMCIlluminatiPass.t.sol`
cover the same scenarios against the new design.

## Launch rehearsal

`.imd/reads/protected/evm_contracts/Contracts.protected.t.sol` was run locally with the real creation
code and constructor arguments `(0x83027ad9d0d5374335086c539dadd1db983441b0, BMC, coordinator,
subscription id)` on chain id 1 with no other contract deployed: the constructor succeeds, the runtime
is within EIP-170 and contains no DELEGATECALL, CALLCODE or SELFDESTRUCT.
