import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  assessTradovateHistoricalCompleteness,
  buildTradovateRepairFillIdCandidates,
} from "./tradovateHistoricalAcquisitionCore.ts"
import { deriveTradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"
import {
  computeTradovateBrokerTradeFinancials,
} from "./tradovateBrokerTradeFinancials.ts"
import {
  TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS,
  TRADOVATE_PERFORMANCE_EXPECTED,
} from "./tradovatePerformanceRegressionConstants.ts"
import {
  assertIncompletePerformanceEconomics,
  assertPerformanceEconomics,
  runTradovateSep2026Pipeline,
  simulateIncrementalBackfill,
  simulateResyncIdempotency,
} from "./tradovateSep2026E2EPipelineCore.ts"
import { reconcileTradovateFinancials } from "./tradovateFinancialReconciliationCore.ts"
import { tradovatePerformanceSep2026FillContexts } from "./tradovatePerformanceSep2026FillPairs.ts"
import { reconstructAllCompletedTrades } from "./tradeReconstruction.ts"
import {
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"

describe("Tradovate historical acquisition + journal P&L (production regression)", () => {
  it("production SYNC A: 33 ledger executions vs 2 remote fills → PARTIAL completeness", () => {
    const remoteFills: TradovateFillRaw[] = [
      {
        id: "660290950341",
        orderId: "1",
        contractId: "4399654",
        timestamp: "2026-09-23T00:48:10.221Z",
        action: "Buy",
        qty: 1,
        price: 1,
      },
      {
        id: "660290950347",
        orderId: "2",
        contractId: "4399654",
        timestamp: "2026-09-23T00:48:48.617Z",
        action: "Sell",
        qty: 1,
        price: 1,
      },
    ]
    const completeness = assessTradovateHistoricalCompleteness({
      ledger: {
        executionCount: 33,
        earliestExecutedAt: "2026-09-14T12:00:00.000Z",
        latestExecutedAt: "2026-09-23T00:48:48.617Z",
        fillIds: new Set(["660290950341"]),
      },
      accountFills: remoteFills,
      incrementalWatermark: "2026-09-23T00:48:48.617Z",
      repairAttempted: true,
      repairFillIdsRequested: [...TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS],
      repairFillIdsRecovered: [],
    })
    assert.equal(completeness.historicalBackfillComplete, false)
    assert.ok(completeness.holesDetected.length >= 3)

    const status = deriveTradovateImportAcquisitionStatus({
      stats: {
        accountId: "65788591",
        orderDepsCount: 2,
        orderIdsCount: 2,
        fillLdepsCount: 2,
        fillListCount: 2,
        mergedUniqueFillCount: 2,
        earliestFillTimestamp: "2026-09-23T00:48:10.221Z",
        latestFillTimestamp: "2026-09-23T00:48:48.617Z",
        fillLdepsBatchErrors: 0,
        orderDepsFailed: false,
        fillListFailed: false,
        fillItemsRepairCount: 0,
        fillItemsRepairRequested: 3,
      },
      acquisitionErrors: [],
      mergedFillCount: 2,
      historicalCompleteness: completeness,
    })
    assert.equal(status, "IMPORT_SUCCESS_PARTIAL")
  })

  it("repair candidates include recovery fills not yet merged", () => {
    const candidates = buildTradovateRepairFillIdCandidates({
      mergedFillIds: new Set(["660290950341"]),
      ledgerFillIds: new Set(["660290950341"]),
    })
    for (const id of TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS) {
      assert.ok(candidates.includes(id), `missing repair candidate ${id}`)
    }
  })

  it("fee PARTIAL: 11 lifecycles keep journal P&L from gross (-100 total)", () => {
    const pipeline = runTradovateSep2026Pipeline({ includeRecoveryFills: false })
    assertIncompletePerformanceEconomics(pipeline)
    assert.equal(pipeline.completed.length, TRADOVATE_PERFORMANCE_EXPECTED.completedLifecyclesIncomplete)

    const contracts = pipeline.contracts
    let withJournal = 0
    let grossTotal = 0
    for (const lc of pipeline.completed) {
      const fin = computeTradovateBrokerTradeFinancials({
        lifecycle: lc,
        contract: contracts.get(String(lc.contractId)),
        contractIdKey: String(lc.contractId),
        feesByFillId: new Map(
          lc.fillIds.map((id) => [
            id,
            {
              totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
              availability: "UNAVAILABLE" as const,
            },
          ])
        ),
      })
      if (fin.journalPnL != null) withJournal += 1
      grossTotal += fin.grossPnL ?? 0
      assert.equal(fin.pnlSource, "gross")
      assert.notEqual(fin.journalPnL, null)
    }
    assert.equal(withJournal, pipeline.completed.length)
    assert.ok(Math.abs(grossTotal + 100) < 0.05)
  })

  it("REPAIR SYNC: recovery fills → 12 lifecycles MNQ/MGC/total -40 idempotent", () => {
    const { syncA, syncB } = simulateIncrementalBackfill()
    assertPerformanceEconomics(syncB)
    const { first, second } = simulateResyncIdempotency()
    assert.equal(first.completed.length, 12)
    assert.equal(second.newExecutions, 0)
    assert.ok(second.duplicateExecutions > 0)
    assert.ok(Math.abs(first.grossByContract.overall + 40) < 0.03)
  })

  it("FillPair partial coverage → INSUFFICIENT_FILLPAIR_COVERAGE not MISMATCH", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const result = reconcileTradovateFinancials({
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      fillPairs: [],
      fillsById: tradovatePerformanceSep2026FillContexts(),
      completed,
      contracts: runTradovateSep2026Pipeline({ includeRecoveryFills: true }).contracts,
      insufficientFillPairData: false,
    })
    assert.equal(result.lifecycleCount, 12)
    assert.equal(result.fillPairCount, 0)
    assert.equal(result.status, "INSUFFICIENT_FILLPAIR_COVERAGE")
    assert.equal(result.difference, null)
  })
})
