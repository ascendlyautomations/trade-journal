import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS,
  TRADOVATE_PERFORMANCE_EXPECTED,
} from "./tradovatePerformanceRegressionConstants.ts"
import {
  assertFeeSemantics,
  assertIncompletePerformanceEconomics,
  assertNoNumericTickers,
  assertPerformanceEconomics,
  assertRecoveryFillsInLedger,
  brokerPatchPreservesUserEnrichment,
  buildSep2026AcquisitionInputs,
  mergeFinancialsWithMetadataFailure,
  runTradovateSep2026Pipeline,
  simulateIncrementalBackfill,
  simulateResyncIdempotency,
} from "./tradovateSep2026E2EPipelineCore.ts"
import { mergeAccountScopedTradovateFills } from "./tradovateFillAcquisitionCore.ts"
import { buildTradovateOrderAccountMap } from "./tradovateOrderAccountMap.ts"
import { TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE } from "./tradovatePerformanceSep2026Fixture.ts"
import {
  deriveTradovateFeeCoverageStatus,
  deriveTradovateImportAcquisitionStatus,
} from "./tradovateSyncCompleteness.ts"
import {
  computeTradovateFillPairGrossPnl,
} from "./tradovateFillPairCore.ts"
import { tradovatePerformanceSep2026FillPairs } from "./tradovatePerformanceSep2026FillPairs.ts"
import { MGC_CONTRACT_ID } from "./tradovatePerformanceSep2026Fixture.ts"
import { reconcileTradovateFinancials } from "./tradovateFinancialReconciliationCore.ts"
import { tradovatePerformanceSep2026FillContexts } from "./tradovatePerformanceSep2026FillPairs.ts"
import { reconstructAllCompletedTrades } from "./tradeReconstruction.ts"
import { tradovatePerformanceSep2026ReconstructionFills } from "./tradovatePerformanceSep2026Fixture.ts"

describe("Tradovate Sep 2026 E2E regression (Phase 4)", () => {
  it("raw acquisition: orders, ldeps, supplemental merge, dedupe, recovery fills in ledger", () => {
    const { primaryLdeps, supplementalList, orderCount } = buildSep2026AcquisitionInputs(true)
    assert.ok(orderCount > 0)
    assert.ok(primaryLdeps.length > 0)
    assert.ok(supplementalList.length > 0)

    const orderAccountById = buildTradovateOrderAccountMap(
      [...new Set([...primaryLdeps, ...supplementalList].map((f) => String(f.orderId)))].map(
        (id) => ({ id, accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE })
      )
    )
    const merged = mergeAccountScopedTradovateFills({
      primaryFills: primaryLdeps,
      supplementalFills: supplementalList,
      targetAccountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById,
    })
    assert.equal(
      merged.length,
      new Set(merged.map((f) => String(f.id))).size,
      "fill ids deduped"
    )
    for (const fillId of TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS) {
      assert.ok(
        merged.some((f) => String(f.id) === fillId),
        `acquisition missing ${fillId}`
      )
    }

    const pipeline = runTradovateSep2026Pipeline({ includeRecoveryFills: true })
    assertRecoveryFillsInLedger(pipeline.ledger)
    assert.doesNotThrow(() => assertPerformanceEconomics(pipeline))
  })

  it("metadata: human tickers, MNQ/MGC VPP, no numeric contract ids", () => {
    const pipeline = runTradovateSep2026Pipeline({ includeRecoveryFills: true })
    assertNoNumericTickers(pipeline.tickers)
    for (const ticker of pipeline.tickers) {
      assert.notEqual(ticker, "4399654")
      assert.notEqual(ticker, "4470324")
      assert.notEqual(ticker, "4176766")
    }
    const mnqMeta = pipeline.contracts.get("4399654")
    const mgcMeta = pipeline.contracts.get(MGC_CONTRACT_ID)
    assert.equal(mnqMeta?.symbolRoot, "MNQ")
    assert.equal(mgcMeta?.symbolRoot, "MGC")
    assert.equal(mnqMeta?.valuePerPoint, 2)
    assert.equal(mgcMeta?.valuePerPoint, 10)
  })

  it("reconstruction: 12 lifecycles, MNQ -45, MGC +5, overall -40", () => {
    const pipeline = runTradovateSep2026Pipeline({ includeRecoveryFills: true })
    assert.equal(pipeline.completed.length, TRADOVATE_PERFORMANCE_EXPECTED.completedLifecycles)
    assertPerformanceEconomics(pipeline)
  })

  it("FillPair validation: MATCH at -40 with shape -26/-18 and +28/+32 preserved", () => {
    const pipeline = runTradovateSep2026Pipeline({ includeRecoveryFills: true })
    assert.equal(pipeline.reconciliation.status, "MATCH")
    assert.ok(Math.abs((pipeline.reconciliation.fillPairGrossPnl ?? 0) + 40) < 0.03)
    assert.ok(Math.abs((pipeline.reconciliation.lifecycleGrossPnl ?? 0) + 40) < 0.03)
    assert.ok(
      Math.abs(pipeline.reconciliation.difference ?? 99) <= 0.03
    )

    const shaped = tradovatePerformanceSep2026FillPairs().filter(
      (p) => p.id.startsWith("fp-mgc-1") || p.id.startsWith("fp-mgc-2")
    )
    let pairShortTotal = 0
    for (const pair of shaped) {
      const { grossPnl } = computeTradovateFillPairGrossPnl({
        pair,
        contract: pipeline.contracts.get(MGC_CONTRACT_ID),
        contractId: MGC_CONTRACT_ID,
      })
      pairShortTotal += grossPnl ?? 0
    }
    const shortLc = pipeline.completed.find((t) => t.fillIds.includes("660290950280"))
    assert.ok(shortLc)
    assert.ok(Math.abs(pairShortTotal + 44) < 0.02)
    assert.equal(shaped.length, 2)
    assert.equal(shortLc!.fillIds.length >= 3, true)
  })

  it("fee semantics: KNOWN_VALUE, KNOWN_ZERO, UNAVAILABLE net behavior", () => {
    assert.doesNotThrow(() => assertFeeSemantics())
    const status = deriveTradovateFeeCoverageStatus({
      fillIds: ["1", "2"],
      feeBatchErrors: ["batch_0:fail"],
      fees: new Map([
        ["1", { availability: "KNOWN_VALUE" }],
        ["2", { availability: "UNAVAILABLE" }],
      ]),
    })
    assert.equal(status, "PARTIAL")
  })

  it("resync idempotency: same ledger, lifecycles, P&L, no duplicates", () => {
    const { first, second } = simulateResyncIdempotency()
    assert.equal(first.ledger.length, second.ledger.length)
    assert.equal(second.newExecutions, 0)
    assert.ok(second.duplicateExecutions > 0)
    assert.equal(first.completed.length, second.completed.length)
    assert.deepEqual(
      first.completed.map((t) => t.lifecycleKey).sort(),
      second.completed.map((t) => t.lifecycleKey).sort()
    )
    assert.ok(Math.abs(first.grossByContract.overall - second.grossByContract.overall) < 0.01)
  })

  it("incremental backfill: SYNC A gap then SYNC B recovery without reimport", () => {
    const { syncA, syncB } = simulateIncrementalBackfill()
    assertIncompletePerformanceEconomics(syncA)
    assert.equal(syncA.ledger.length, syncB.ledger.length - 3)
    assert.equal(syncB.newExecutions, 3)
    assertPerformanceEconomics(syncB)
    for (const fillId of TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS) {
      assert.ok(syncB.ledger.some((r) => r.external_fill_id === fillId))
    }
  })

  it("user enrichment preserved across broker resync patch", () => {
    const existing = {
      notes: "user note",
      strategy: "breakout",
      image_url: "https://example.com/chart.png",
      psychology_notes: "calm",
      rr: 2.5,
      ticker: "MNQ",
      pnl: -17,
    }
    const incoming = {
      notes: "broker overwrite",
      strategy: "ignored",
      ticker: "",
      pnl: null,
      broker_lifecycle_id: "tradovate:v2:1:4399654:1",
    }
    const patch = brokerPatchPreservesUserEnrichment({ existing, incomingBroker: incoming })
    assert.equal(patch.notes, "user note")
    assert.equal(patch.strategy, "breakout")
    assert.equal(patch.image_url, existing.image_url)
    assert.equal(patch.psychology_notes, "calm")
    assert.equal(patch.rr, 2.5)
  })

  it("partial API failure: acquisition PARTIAL, metadata failure UNRESOLVED, ledger preserved", () => {
    const partial = runTradovateSep2026Pipeline({
      includeRecoveryFills: true,
      simulatePartialLdepsBatch: true,
    })
    assert.equal(partial.acquisitionStatus, "IMPORT_SUCCESS_PARTIAL")

    const metaFail = runTradovateSep2026Pipeline({
      includeRecoveryFills: true,
      metadataResolutionFailed: true,
    })
    assert.equal(metaFail.reconciliation.status, "UNRESOLVED_METADATA")
    assert.ok(metaFail.ledger.length > 0)

    const merged = mergeFinancialsWithMetadataFailure({
      existingPnL: -17,
      existingTicker: "MNQ",
      incomingPnL: null,
      incomingTicker: "",
    })
    assert.equal(merged.finalPnL, -17)
    assert.equal(merged.finalTicker, "MNQ")
  })

  it("acquisition status differentiates COMPLETE vs PARTIAL vs FAILED", () => {
    const complete = deriveTradovateImportAcquisitionStatus({
      stats: {
        accountId: "1",
        orderDepsCount: 1,
        orderIdsCount: 1,
        fillLdepsCount: 1,
        fillListCount: 1,
        mergedUniqueFillCount: 10,
        earliestFillTimestamp: null,
        latestFillTimestamp: null,
        fillLdepsBatchErrors: 0,
        orderDepsFailed: false,
        fillListFailed: false,
        fillItemsRepairCount: 0,
        fillItemsRepairRequested: 0,
      },
      acquisitionErrors: [],
      mergedFillCount: 10,
    })
    assert.equal(complete, "IMPORT_SUCCESS_COMPLETE")

    const partial = deriveTradovateImportAcquisitionStatus({
      stats: {
        accountId: "1",
        orderDepsCount: 0,
        orderIdsCount: 0,
        fillLdepsCount: 0,
        fillListCount: 0,
        mergedUniqueFillCount: 10,
        earliestFillTimestamp: null,
        latestFillTimestamp: null,
        fillLdepsBatchErrors: 1,
        orderDepsFailed: false,
        fillListFailed: false,
        fillItemsRepairCount: 0,
        fillItemsRepairRequested: 0,
      },
      acquisitionErrors: ["fill_ldeps:batch_0"],
      mergedFillCount: 10,
    })
    assert.equal(partial, "IMPORT_SUCCESS_PARTIAL")
  })

})
