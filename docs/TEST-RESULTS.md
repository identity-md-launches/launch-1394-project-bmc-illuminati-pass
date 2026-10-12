# Foundry test results

Recorded 2026-10-12 with forge 1.8.3, solc 0.8.26 (`forge test`, default profile, fuzz runs 64).

```
No files changed, compilation skipped
Ran 4 tests for test/ChainlinkMockIntegration.t.sol:ChainlinkMockIntegrationTest
[PASS] test_NotAConsumerReverts() (gas: 369271)
[PASS] test_RequestAndFulfilThroughChainlinkMock() (gas: 759243)
[PASS] test_SeveralRequestsOutOfOrderThroughChainlinkMock() (gas: 1890718)
[PASS] test_UnfundedSubscriptionKeepsTokenPendingUntilFunded() (gas: 949212)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 14.89ms (3.25ms CPU time)
Ran 39 tests for test/BMCIlluminatiPass.t.sol:BMCIlluminatiPassTest
[PASS] testFuzz_SingleRevealAlwaysInInventory(uint256) (runs: 64, μ: 11045582, ~: 11043499)
[PASS] test_CIDSetOnce() (gas: 176633)
[PASS] test_CallbackBatchIsGasAware() (gas: 12140393)
[PASS] test_Constants() (gas: 82402)
[PASS] test_DeployScriptConfig() (gas: 10655354)
[PASS] test_DeployScriptRequiresOwner() (gas: 5700916)
[PASS] test_ExcessAllowanceOnlyBurnsPrice() (gas: 343854)
[PASS] test_FinalizationOrderCannotBeChosen() (gas: 12020044)
[PASS] test_FirstMinterGetsLegendaryGenesis1() (gas: 2027697)
[PASS] test_FulfillRevealsAndLocksMetadata() (gas: 17335801)
[PASS] test_Full500MintSimulation() (gas: 269030345)
[PASS] test_FullMintOutWithInOrderFulfillment() (gas: 235375333)
[PASS] test_GenesisRevertsAfterPhase1() (gas: 10618021)
[PASS] test_Mints2To40AreSequentialGenesis() (gas: 14434063)
[PASS] test_MysteryBurnRevertsIfVRFRequestFails() (gas: 10752056)
[PASS] test_MysteryRevertsDuringPhase1() (gas: 460015)
[PASS] test_MysteryRevertsWhenVRFUnconfigured() (gas: 10677451)
[PASS] test_NoOwnerMintOrWithdrawSurface() (gas: 87601)
[PASS] test_OnlyCoordinatorCanFulfill() (gas: 10961327)
[PASS] test_OutOfOrderFulfillmentFinalizesInMintOrder() (gas: 12222761)
[PASS] test_PendingMetadataIsNeutral() (gas: 13645572)
[PASS] test_PermissionlessFinalizationWhenCallbackGasTooLow() (gas: 11129061)
[PASS] test_Phase1CostsExactlyOneMillion() (gas: 392359)
[PASS] test_Phase2CostsExactly350k() (gas: 11016795)
[PASS] test_ReentrancyGenesisBlocked() (gas: 895572)
[PASS] test_ReentrancyMysteryBlocked() (gas: 11439483)
[PASS] test_RevertInsufficientAllowance() (gas: 181320)
[PASS] test_RevertInsufficientBalance() (gas: 195192)
[PASS] test_RevertNoAllowance() (gas: 146266)
[PASS] test_RevertWhenTokenDecimalsUnexpected() (gas: 810941)
[PASS] test_RevertWhenTokenDoesNotActuallyBurn() (gas: 827407)
[PASS] test_StandardArtCombinationsUnique() (gas: 1482850)
[PASS] test_StandardArtCoversEveryTrait() (gas: 743721)
[PASS] test_StandardArtRendersWithoutGenesisTraits() (gas: 30070221)
[PASS] test_StandardMetadataAfterReveal() (gas: 20024385)
[PASS] test_TransfersAreStandard() (gas: 471691)
[PASS] test_UnavailableRandomnessStaysPendingNoFallback() (gas: 11056275)
[PASS] test_VRFConfigValidation() (gas: 252736)
[PASS] test_ViewsRevertForNonexistent() (gas: 33573)
Suite result: ok. 39 passed; 0 failed; 0 skipped; finished in 323.95ms (1.25s CPU time)
Ran 2 test suites in 325.44ms (338.84ms CPU time): 43 tests passed, 0 failed, 0 skipped (43 total tests)
```

Contract size (`forge build --sizes`): BMCIlluminatiPass runtime 23,529 bytes, 1,047 bytes under the EIP-170 limit.
